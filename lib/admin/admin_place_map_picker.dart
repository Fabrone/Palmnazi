import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import 'package:palmnazi/config/maps_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AdminPlaceMapPicker
//
// Interactive Google Map for selecting a place location.
//
// Features:
//   • Full Google Map with satellite + normal toggle
//   • Search by name → results plotted as markers on the map
//   • Tap any marker to select that location
//   • Tap anywhere on the map to drop a pin
//   • Drag the pin to fine-tune exact position
//   • Reverse geocoding: pin → human-readable address
//   • Kenya-centric default view (Nairobi) if no initial position
//
// Returns a [PlaceLocationResult] with address, lat, lng when the user
// confirms their selection.
// ─────────────────────────────────────────────────────────────────────────────

class PlaceLocationResult {
  final String address;
  final double latitude;
  final double longitude;

  const PlaceLocationResult({
    required this.address,
    required this.latitude,
    required this.longitude,
  });
}

// ── Map error classification (pattern adapted from CoffeeCore's
//    FarmMapScreen) ───────────────────────────────────────────────────────
//
// NOTE: an unactivated/misconfigured Maps JavaScript API key throws its
// error to the browser console, not into Dart's catch zones, so it can't be
// classified directly — that case is caught by the load watchdog below
// instead (see _startLoadWatchdog). This classifier handles errors that DO
// surface in Dart: REST call failures from search/geocoding, and anything
// thrown inside onMapCreated.
enum MapErrorType { apiKeyInvalid, mapLoadFailed, networkError, unknownError }

class MapErrorInfo {
  final MapErrorType type;
  final String userMessage;
  final String technicalDetails;

  const MapErrorInfo({
    required this.type,
    required this.userMessage,
    required this.technicalDetails,
  });
}

MapErrorInfo _parseMapError(dynamic error, {String? context}) {
  final s = error.toString();
  if (s.contains('RefererNotAllowedMapError') ||
      s.contains('ApiNotActivatedMapError') ||
      s.contains('API key') ||
      s.contains('API_KEY')) {
    return MapErrorInfo(
      type: MapErrorType.apiKeyInvalid,
      userMessage: 'Map service key issue — this usually needs a Cloud '
          'console fix, not a retry.',
      technicalDetails: '[$context] $s',
    );
  }
  if (s.contains('SocketException') ||
      s.contains('TimeoutException') ||
      s.contains('Connection')) {
    return MapErrorInfo(
      type: MapErrorType.networkError,
      userMessage: 'Connection problem — check your internet and try again.',
      technicalDetails: '[$context] $s',
    );
  }
  return MapErrorInfo(
    type: MapErrorType.unknownError,
    userMessage: 'Something went wrong loading the map.',
    technicalDetails: '[$context] $s',
  );
}

class AdminPlaceMapPicker extends StatefulWidget {
  /// Initial camera position. If null, defaults to Nairobi, Kenya.
  final CameraPosition? initialCameraPosition;

  /// Pre-selected location (shown as a draggable marker).
  final LatLng? initialSelectedLocation;

  const AdminPlaceMapPicker({
    super.key,
    this.initialCameraPosition,
    this.initialSelectedLocation,
  });

  @override
  State<AdminPlaceMapPicker> createState() => _AdminPlaceMapPickerState();
}

class _AdminPlaceMapPickerState extends State<AdminPlaceMapPicker> {
  GoogleMapController? _mapController;
  MapType _mapType = MapType.hybrid;

  // ── Map load state (CoffeeCore-style crash/fallback pattern) ────────────
  bool _isMapCrash = false;
  String? _mapErrorMessage;
  Timer? _loadWatchdog;

  // ── Search state ─────────────────────────────────────────────────────────
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounceTimer;
  bool _searching = false;
  List<Map<String, dynamic>> _searchResults = [];

  // ── Selected pin ─────────────────────────────────────────────────────────
  LatLng? _selectedLocation;
  String? _resolvedAddress;
  bool _resolvingAddress = false;

  // ── Map markers ────────────────────────────────────────────────────────────
  final Set<Marker> _markers = {};

  // ── Kenya default ────────────────────────────────────────────────────────
  static const LatLng _kenyaCenter = LatLng(-1.2921, 36.8219);
  static const double _defaultZoom = 13.0;

  @override
  void initState() {
    super.initState();
    if (widget.initialSelectedLocation != null) {
      _selectedLocation = widget.initialSelectedLocation;
      _resolvedAddress = null; // will be fetched on map ready
    }
    _startLoadWatchdog();
  }

  // If onMapCreated hasn't fired within 5s, the JS Maps SDK almost certainly
  // failed silently (unactivated API / billing / referrer issue) — surface
  // that instead of leaving a blank screen. Search/geocoding below are REST
  // calls on a separate key and keep working regardless of this state.
  void _startLoadWatchdog() {
    _loadWatchdog?.cancel();
    setState(() {
      _isMapCrash = false;
      _mapErrorMessage = null;
    });
    _loadWatchdog = Timer(const Duration(seconds: 5), () {
      if (!mounted || _mapController != null) return;
      debugPrint('⚠️ [MapPicker] Map did not initialize within 5s — '
          'likely an unactivated/misconfigured Maps API key.');
      setState(() {
        _isMapCrash = true;
        _mapErrorMessage = 'The visual map preview isn\'t loading — this '
            'usually means the Maps service isn\'t fully activated for this '
            'app yet.';
      });
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _loadWatchdog?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  // ── Search: Places Text Search ───────────────────────────────────────────
  //
  // Uses the Places API Text Search endpoint (better for Kenya than
  // Autocomplete because it returns lat/lng directly and ranks by prominence).
  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    final trimmed = query.trim();

    if (trimmed.length < 2) {
      setState(() {
        _searchResults = [];
        _searching = false;
      });
      return;
    }

    setState(() => _searching = true);

    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      await _performTextSearch(trimmed);
    });
  }

  Future<void> _performTextSearch(String query) async {
    if (!MapsConfig.hasPlacesKey) {
      setState(() => _searching = false);
      return;
    }

    try {
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/textsearch/json',
        {
          'query': query,
          'region': 'ke', // Kenya bias
          'key': MapsConfig.placesApiKey,
        },
      );

      debugPrint('🔍 [MapPicker/TextSearch] query="$query"');
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (!mounted) return;

      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final status = body['status'] as String? ?? '';
        final results = (body['results'] as List<dynamic>?) ?? [];

        debugPrint('   ↳ status=$status  results=${results.length}');

        if (status != 'OK' || results.isEmpty) {
          setState(() {
            _searchResults = [];
            _searching = false;
          });
          return;
        }

        final mapped = results.map<Map<String, dynamic>>((r) {
          final geo = r['geometry'] as Map<String, dynamic>?;
          final loc = geo?['location'] as Map<String, dynamic>?;
          return {
            'place_id': r['place_id'] as String? ?? '',
            'name': r['name'] as String? ?? '',
            'address': r['formatted_address'] as String? ?? '',
            'lat': (loc?['lat'] as num?)?.toDouble(),
            'lng': (loc?['lng'] as num?)?.toDouble(),
          };
        }).where((r) => r['lat'] != null && r['lng'] != null).toList();

        setState(() {
          _searchResults = mapped;
          _searching = false;
        });

        // Auto-fit map to show all results
        if (mapped.length > 1) {
          _fitToResults(mapped);
        } else if (mapped.length == 1) {
          final lat = mapped.first['lat'] as double;
          final lng = mapped.first['lng'] as double;
          _moveCamera(LatLng(lat, lng), zoom: 16);
        }
      } else {
        debugPrint('⚠️ [MapPicker/TextSearch] HTTP ${resp.statusCode}');
        setState(() => _searching = false);
      }
    } catch (e) {
      final info = _parseMapError(e, context: 'Places Text Search');
      debugPrint('❌ [MapPicker/TextSearch] ${info.technicalDetails}');
      if (mounted) setState(() => _searching = false);
    }
  }

  // ── Camera helpers ───────────────────────────────────────────────────────

  void _moveCamera(LatLng target, {double zoom = 16}) {
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: target, zoom: zoom),
      ),
    );
  }

  void _fitToResults(List<Map<String, dynamic>> results) {
    if (results.isEmpty || _mapController == null) return;

    final lats = results.map((r) => r['lat'] as double).toList();
    final lngs = results.map((r) => r['lng'] as double).toList();

    final sw = LatLng(
      lats.reduce((a, b) => a < b ? a : b),
      lngs.reduce((a, b) => a < b ? a : b),
    );
    final ne = LatLng(
      lats.reduce((a, b) => a > b ? a : b),
      lngs.reduce((a, b) => a > b ? a : b),
    );

    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(southwest: sw, northeast: ne),
        60, // padding in pixels
      ),
    );
  }

  // ── Pin placement ──────────────────────────────────────────────────────────

  void _onMapTapped(LatLng position) {
    debugPrint('📍 [MapPicker] Map tapped at $position');
    _setSelectedLocation(position);
  }

  void _onSearchResultTapped(Map<String, dynamic> result) {
    final lat = result['lat'] as double;
    final lng = result['lng'] as double;
    final address = result['address'] as String? ?? '';
    final name = result['name'] as String? ?? '';

    final position = LatLng(lat, lng);
    debugPrint('📍 [MapPicker] Result tapped: $name @ $position');

    _setSelectedLocation(position, preResolvedAddress: address.isNotEmpty ? address : null);
    _moveCamera(position, zoom: 18);

    setState(() {
      _searchResults = [];
      _searchCtrl.text = name;
      _searchFocus.unfocus();
    });
  }

  void _setSelectedLocation(LatLng position, {String? preResolvedAddress}) {
    setState(() {
      _selectedLocation = position;
      _resolvedAddress = preResolvedAddress;
      _resolvingAddress = preResolvedAddress == null;
      _markers.clear();
      _markers.add(
        Marker(
          markerId: const MarkerId('selected_pin'),
          position: position,
          draggable: true,
          onDragEnd: _onMarkerDragged,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: 'Selected Location'),
        ),
      );
    });

    if (preResolvedAddress == null) {
      _reverseGeocode(position);
    }
  }

  void _onMarkerDragged(LatLng newPosition) {
    debugPrint('📍 [MapPicker] Marker dragged to $newPosition');
    _setSelectedLocation(newPosition);
  }

  // ── Reverse Geocoding ──────────────────────────────────────────────────────
  //
  // Converts lat/lng → human-readable address using Geocoding API.
  Future<void> _reverseGeocode(LatLng position) async {
    if (!MapsConfig.hasPlacesKey) return;

    setState(() => _resolvingAddress = true);

    try {
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/geocode/json',
        {
          'latlng': '${position.latitude},${position.longitude}',
          'key': MapsConfig.placesApiKey,
        },
      );

      debugPrint('🌍 [MapPicker/Geocode] reverse geocode $position');
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      if (!mounted) return;

      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final status = body['status'] as String? ?? '';
        final results = (body['results'] as List<dynamic>?) ?? [];

        if (status == 'OK' && results.isNotEmpty) {
          final address = results.first['formatted_address'] as String? ?? '';
          debugPrint('   ↳ address="$address"');
          setState(() {
            _resolvedAddress = address;
            _resolvingAddress = false;
          });
          return;
        }
      }
    } catch (e) {
      debugPrint('❌ [MapPicker/Geocode] $e');
    }

    if (mounted) setState(() => _resolvingAddress = false);
  }

  // ── Confirm selection ────────────────────────────────────────────────────

  void _confirmSelection() {
    if (_selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Tap the map or search to select a location first.'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    final result = PlaceLocationResult(
      address: _resolvedAddress ?? '',
      latitude: _selectedLocation!.latitude,
      longitude: _selectedLocation!.longitude,
    );

    Navigator.of(context).pop(result);
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final initialTarget = widget.initialSelectedLocation ?? _kenyaCenter;
    final initialZoom = widget.initialSelectedLocation != null ? 16.0 : _defaultZoom;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Select Location on Map',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        actions: [
          // Map type toggle
          IconButton(
            icon: Icon(
              _mapType == MapType.hybrid
                  ? Icons.map_outlined
                  : Icons.satellite_alt,
              color: Colors.white70,
            ),
            tooltip: _mapType == MapType.hybrid ? 'Normal Map' : 'Satellite',
            onPressed: () {
              setState(() {
                _mapType = _mapType == MapType.hybrid
                    ? MapType.normal
                    : MapType.hybrid;
              });
            },
          ),
          // Confirm button
          TextButton.icon(
            onPressed: _selectedLocation != null ? _confirmSelection : null,
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('CONFIRM', style: TextStyle(fontWeight: FontWeight.w600)),
            style: TextButton.styleFrom(
              foregroundColor: _selectedLocation != null
                  ? const Color(0xFF14FFEC)
                  : Colors.white24,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // ── Search bar ───────────────────────────────────────────────────
          Container(
            color: const Color(0xFF111827),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _searchCtrl,
                  focusNode: _searchFocus,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'Search for a place, hotel, restaurant, area…',
                    hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded,
                        color: Colors.white38, size: 18),
                    suffixIcon: _searching
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Color(0xFF14FFEC)),
                            ),
                          )
                        : _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded,
                                    color: Colors.white38, size: 16),
                                onPressed: () {
                                  setState(() {
                                    _searchCtrl.clear();
                                    _searchResults = [];
                                  });
                                },
                              )
                            : null,
                    filled: true,
                    fillColor: const Color(0xFF0D1117),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF14FFEC)),
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  ),
                ),

                // ── Search results dropdown ────────────────────────────────
                if (_searchResults.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 220),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F2937),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: _searchResults.length,
                        separatorBuilder: (_, __) => const Divider(
                            color: Colors.white10, height: 1),
                        itemBuilder: (_, i) {
                          final r = _searchResults[i];
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => _onSearchResultTapped(r),
                              highlightColor:
                                  const Color(0xFF14FFEC).withValues(alpha: 0.07),
                              splashColor:
                                  const Color(0xFF14FFEC).withValues(alpha: 0.04),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 11),
                                child: Row(children: [
                                  Container(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF14FFEC)
                                          .withValues(alpha: 0.08),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.place_rounded,
                                        color: Color(0xFF14FFEC), size: 14),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          r['name'] as String? ?? '',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500),
                                        ),
                                        if ((r['address'] as String?)
                                                ?.isNotEmpty ??
                                            false) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            r['address'] as String,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                color: Colors.white38,
                                                fontSize: 11),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                      Icons.arrow_forward_ios_rounded,
                                      color: Colors.white24,
                                      size: 11),
                                ]),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],

                // ── No results message ─────────────────────────────────────
                if (!_searching &&
                    _searchCtrl.text.trim().length >= 2 &&
                    _searchResults.isEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: const Row(children: [
                      Icon(Icons.search_off_rounded,
                          color: Colors.white24, size: 14),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'No results found. Try a different name, or tap directly on the map.',
                          style: TextStyle(
                              color: Colors.white38, fontSize: 11, height: 1.4),
                        ),
                      ),
                    ]),
                  ),
                ],
              ],
            ),
          ),

          // ── Selected location info bar ───────────────────────────────────
          if (_selectedLocation != null)
            Container(
              width: double.infinity,
              color: const Color(0xFF0D1117),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.location_on_rounded,
                        color: Color(0xFF14FFEC), size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _resolvedAddress != null && _resolvedAddress!.isNotEmpty
                            ? _resolvedAddress!
                            : 'Lat: ${_selectedLocation!.latitude.toStringAsFixed(6)}, '
                                'Lng: ${_selectedLocation!.longitude.toStringAsFixed(6)}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12, height: 1.4),
                      ),
                    ),
                  ]),
                  if (_resolvingAddress) ...[
                    const SizedBox(height: 6),
                    const Row(children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFF14FFEC)),
                      ),
                      SizedBox(width: 8),
                      Text('Resolving address…',
                          style: TextStyle(
                              color: Colors.white38, fontSize: 11)),
                    ]),
                  ],
                ],
              ),
            ),

          // ── Map ──────────────────────────────────────────────────────────
          Expanded(child: _buildMapArea(initialTarget, initialZoom)),

          // ── Bottom hint ──────────────────────────────────────────────────
          Container(
            width: double.infinity,
            color: const Color(0xFF111827),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: const Row(children: [
              Icon(Icons.touch_app_rounded,
                  color: Colors.white24, size: 14),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Tap anywhere on the map to drop a pin. Drag the pin to fine-tune. Search above to find named places.',
                  style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.4),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  // ── Map area: live GoogleMap, or fallback if it never loaded ────────────
  Widget _buildMapArea(LatLng initialTarget, double initialZoom) {
    if (_isMapCrash) {
      return Container(
        width: double.infinity,
        color: const Color(0xFF0D1117),
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.map_outlined, size: 48, color: Colors.white24),
              const SizedBox(height: 14),
              const Text(
                'Map Preview Unavailable',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                _mapErrorMessage ?? 'The map service is unavailable.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white60, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 6),
              const Text(
                'Good news: search above and Confirm still work without it — '
                'only tap-to-drop-pin and drag-to-adjust need the visual map.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Color(0xFF14FFEC), fontSize: 11.5, height: 1.4),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    onPressed: _startLoadWatchdog,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Retry'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF14FFEC),
                      side: const BorderSide(color: Color(0xFF14FFEC)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style:
                        TextButton.styleFrom(foregroundColor: Colors.white60),
                    child: const Text('Close & Enter Manually'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return GoogleMap(
      mapType: _mapType,
      initialCameraPosition: CameraPosition(
        target: initialTarget,
        zoom: initialZoom,
      ),
      onMapCreated: (ctrl) {
        try {
          _mapController = ctrl;
          _loadWatchdog?.cancel();
          // If we have a pre-selected location, show it
          if (_selectedLocation != null) {
            _setSelectedLocation(_selectedLocation!,
                preResolvedAddress: _resolvedAddress);
          }
        } catch (e) {
          final info = _parseMapError(e, context: 'Map Creation');
          debugPrint('❌ [MapPicker] ${info.technicalDetails}');
          if (mounted) {
            setState(() {
              _isMapCrash = true;
              _mapErrorMessage = info.userMessage;
            });
          }
        }
      },
      onTap: _onMapTapped,
      markers: _markers,
      myLocationEnabled: false, // admin is selecting, not using device GPS
      myLocationButtonEnabled: false,
      zoomControlsEnabled: true,
      mapToolbarEnabled: false,
      compassEnabled: true,
    );
  }
}