import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import 'package:palmnazi/admin/admin_api_service.dart';
import 'package:palmnazi/admin/admin_shared_widgets.dart';
import 'package:palmnazi/models/city_model.dart';
import 'package:palmnazi/models/category_model.dart';
import 'package:palmnazi/models/place_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AdminPlaceWizardScreen
//
// Full-screen 11-step wizard for creating or editing a Place.
//
// Step 1:  Create draft          → POST /api/places
// Step 2:  Basic info            → PATCH /api/places/:id
// Step 3:  Location              → PATCH /api/places/:id/location
// Step 4:  Contact               → PATCH /api/places/:id/contact
// Step 5:  Attributes            → PATCH /api/places/:id/attributes
// Step 6:  Nested data           → POST /api/places/:id/rooms (accommodation)
//                                  POST /api/places/:id/menu-sections + menu-items (dining)
//                                  POST /api/places/:id/shows + performances (entertainment)
//                                  POST /api/places/:id/exhibitions + artifacts (cultural)
// Step 7:  Media                 → PATCH /api/places/:id/media
// Step 8:  Booking & pricing     → PATCH /api/places/:id/booking
// Step 9:  Link categories       → PUT /api/places/:id/categories
// Step 10: Validate              → GET /api/places/:id/submit
// Step 11: Submit                → POST /api/places/:id/submit
// ─────────────────────────────────────────────────────────────────────────────

class AdminPlaceWizardScreen extends StatefulWidget {
  final AdminApiService apiService;
  final List<CityModel> cities;
  final List<CategoryModel> categories;
  final PlaceModel? existingPlace;

  const AdminPlaceWizardScreen({
    super.key,
    required this.apiService,
    required this.cities,
    required this.categories,
    this.existingPlace,
  });

  @override
  State<AdminPlaceWizardScreen> createState() => _AdminPlaceWizardScreenState();
}

class _AdminPlaceWizardScreenState extends State<AdminPlaceWizardScreen> {
  int _step = 0;
  bool _saving = false;
  String? _stepError;

  PlaceModel? _place;

  // ── Step 1 — Draft
  final _nameCtrl = TextEditingController();
  String? _selectedCityId;
  String? _primaryCategorySlug;

  // ── Step 2 — Basic info
  final _shortDescCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _areaCtrl = TextEditingController();

  // ── Step 3 — Location
  final _addressCtrl = TextEditingController();
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();

  // ── Step 4 — Contact
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _websiteCtrl = TextEditingController();

  // ── Step 5 — Attributes (category-aware)
  final _checkInCtrl = TextEditingController();
  final _checkOutCtrl = TextEditingController();
  final _starRatingCtrl = TextEditingController();
  final _amenitiesCtrl = TextEditingController();
  final _cuisineCtrl = TextEditingController();
  final _seatingCapCtrl = TextEditingController();
  final _openingHoursCtrl = TextEditingController();

  // ── Step 6 — Nested data (built as lists, submitted in one POST)
  final List<Map<String, dynamic>> _rooms = [];
  final List<Map<String, dynamic>> _menuSections = [];
  final List<Map<String, dynamic>> _menuItems = [];
  final List<Map<String, dynamic>> _shows = [];

  // ── Step 7 — Media
  final _coverImageCtrl = TextEditingController();
  final List<TextEditingController> _imageUrlCtrls = [TextEditingController()];

  // Step 7 — upload state (cover)
  Uint8List? _coverImageBytes;
  bool _uploadingCover = false;
  double _coverUploadProgress = 0.0;

  // Step 7 — upload state (gallery — parallel to _imageUrlCtrls)
  final List<Uint8List?> _galleryBytes = [null];
  final List<bool> _galleryUploading = [false];
  final List<double> _galleryProgress = [0.0];

  // ── Step 8 — Booking
  bool _isBookable = false;
  final _minPriceCtrl = TextEditingController();
  final _maxPriceCtrl = TextEditingController();
  String _priceUnit = 'night';
  String _currency = 'KES';
  String _cancellationPolicy = 'flexible';

  // ── Step 9 — Categories (multi-select)
  final Set<String> _selectedCategoryIds = {};

  // ── Step 10 — Validation result
  PlaceValidationResult? _validationResult;

  @override
  void initState() {
    super.initState();
    if (widget.existingPlace != null) {
      _preloadFromExisting(widget.existingPlace!);
    }
  }

  void _preloadFromExisting(PlaceModel p) {
    _place = p;
    _step = 1; // Skip to step 2 for editing
    _nameCtrl.text = p.name;
    _selectedCityId = p.cityId;
    _shortDescCtrl.text = p.shortDescription ?? '';
    _descCtrl.text = p.description ?? '';
    _areaCtrl.text = p.area ?? '';
    _addressCtrl.text = p.address ?? '';
    _latCtrl.text = p.latitude?.toString() ?? '';
    _lngCtrl.text = p.longitude?.toString() ?? '';
    _phoneCtrl.text = p.contact?.phone ?? '';
    _emailCtrl.text = p.contact?.email ?? '';
    _websiteCtrl.text = p.contact?.website ?? '';
    _coverImageCtrl.text = p.coverImage ?? '';
    _isBookable = p.isBookable;
    _minPriceCtrl.text = p.pricing?.min?.toString() ?? '';
    _maxPriceCtrl.text = p.pricing?.max?.toString() ?? '';
    _priceUnit = p.pricing?.unit ?? 'night';
    _currency = p.pricing?.currency ?? 'KES';
    for (final link in p.categoryLinks) {
      _selectedCategoryIds.add(link.categoryId);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _shortDescCtrl.dispose(); _descCtrl.dispose();
    _areaCtrl.dispose(); _addressCtrl.dispose(); _latCtrl.dispose();
    _lngCtrl.dispose(); _phoneCtrl.dispose(); _emailCtrl.dispose();
    _websiteCtrl.dispose(); _coverImageCtrl.dispose();
    _checkInCtrl.dispose(); _checkOutCtrl.dispose(); _starRatingCtrl.dispose();
    _amenitiesCtrl.dispose(); _cuisineCtrl.dispose(); _seatingCapCtrl.dispose();
    _openingHoursCtrl.dispose(); _minPriceCtrl.dispose(); _maxPriceCtrl.dispose();
    for (final c in _imageUrlCtrls) { c.dispose(); }
    // _galleryBytes / _galleryUploading / _galleryProgress are plain lists —
    // no extra dispose needed; they GC with the state.
    super.dispose();
  }

  // ── Category type helpers ────────────────────────────────────────────────

  bool get _isAccommodationType {
    final slug = _primaryCategorySlug ?? '';
    return slug.contains('accommodation') || slug.contains('hotel') ||
        slug.contains('resort') || slug.contains('lodge');
  }

  bool get _isDiningType {
    final slug = _primaryCategorySlug ?? '';
    return slug.contains('dining') || slug.contains('restaurant') ||
        slug.contains('food') || slug.contains('cafe');
  }

  bool get _isEntertainmentType {
    final slug = _primaryCategorySlug ?? '';
    return slug.contains('entertainment') || slug.contains('event') ||
        slug.contains('show') || slug.contains('cinema');
  }

  bool get _isCulturalType {
    final slug = _primaryCategorySlug ?? '';
    return slug.contains('museum') || slug.contains('cultural') ||
        slug.contains('heritage') || slug.contains('art');
  }

  String get _nestedDataLabel {
    if (_isAccommodationType) return 'Rooms';
    if (_isDiningType) return 'Menu';
    if (_isEntertainmentType) return 'Shows';
    if (_isCulturalType) return 'Exhibitions';
    return 'Details';
  }

  // ── Step 7: cover image upload ────────────────────────────────────────────

  Future<void> _pickAndUploadCoverImage() async {
    // ── FIX: Resolve FirebaseStorage.instance BEFORE the file-picker await.
    //
    // On Flutter Web, FilePicker resolves through an HTML file-input JS callback.
    // Accessing FirebaseStorage.instance (→ Firebase.app() → firebase_core_web)
    // inside that JS continuation throws:
    //   "type 'FirebaseException' is not a subtype of type 'JavaScriptObject'"
    // Capturing synchronously here keeps the call on the Dart side.
    final FirebaseStorage storage = FirebaseStorage.instance;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) return;

    final ext = (file.extension ?? 'jpg').toLowerCase();
    final contentType = _mimeFor(ext);
    final nameSlug = _nameSlug();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final storagePath = 'place-covers/$nameSlug-$ts.$ext';

    setState(() {
      _coverImageBytes = bytes;
      _uploadingCover = true;
      _coverUploadProgress = 0.0;
    });

    try {
      final ref = storage.ref(storagePath);
      final task = ref.putData(bytes, SettableMetadata(contentType: contentType));
      task.snapshotEvents.listen((s) {
        if (mounted && s.totalBytes > 0) {
          setState(() => _coverUploadProgress = s.bytesTransferred / s.totalBytes);
        }
      });
      await task;
      final url = await ref.getDownloadURL();
      if (mounted) {
        setState(() {
          _coverImageCtrl.text = url;
          _uploadingCover = false;
          _coverUploadProgress = 1.0;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _uploadingCover = false;
          _coverImageBytes = null;
          _coverUploadProgress = 0.0;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Cover upload failed: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  // ── Step 7: gallery image upload (per-slot) ───────────────────────────────

  Future<void> _pickAndUploadGalleryImage(int index) async {
    // ── FIX: Same as cover upload — capture FirebaseStorage.instance BEFORE
    // the FilePicker await to avoid the flutter-web JS interop TypeError.
    final FirebaseStorage storage = FirebaseStorage.instance;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) return;

    final ext = (file.extension ?? 'jpg').toLowerCase();
    final contentType = _mimeFor(ext);
    final nameSlug = _nameSlug();
    final ts = DateTime.now().millisecondsSinceEpoch;
    // index+1 so filenames start at 1 to match the gallery ordering
    final storagePath = 'place-gallery/$nameSlug-${index + 1}-$ts.$ext';

    setState(() {
      _galleryBytes[index] = bytes;
      _galleryUploading[index] = true;
      _galleryProgress[index] = 0.0;
    });

    try {
      final ref = storage.ref(storagePath);
      final task = ref.putData(bytes, SettableMetadata(contentType: contentType));
      task.snapshotEvents.listen((s) {
        if (mounted && s.totalBytes > 0) {
          setState(() => _galleryProgress[index] = s.bytesTransferred / s.totalBytes);
        }
      });
      await task;
      final url = await ref.getDownloadURL();
      if (mounted) {
        setState(() {
          _imageUrlCtrls[index].text = url;
          _galleryUploading[index] = false;
          _galleryProgress[index] = 1.0;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _galleryUploading[index] = false;
          _galleryBytes[index] = null;
          _galleryProgress[index] = 0.0;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gallery image upload failed: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  // ── Gallery slot management (keeps parallel lists in sync) ────────────────

  void _addGallerySlot() {
    setState(() {
      _imageUrlCtrls.add(TextEditingController());
      _galleryBytes.add(null);
      _galleryUploading.add(false);
      _galleryProgress.add(0.0);
    });
  }

  void _removeGallerySlot(int index) {
    _imageUrlCtrls[index].dispose();
    setState(() {
      _imageUrlCtrls.removeAt(index);
      _galleryBytes.removeAt(index);
      _galleryUploading.removeAt(index);
      _galleryProgress.removeAt(index);
    });
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// URL-safe slug derived from the place name — used in storage paths.
  String _nameSlug() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return 'place';
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '-');
  }

  String _mimeFor(String ext) {
    switch (ext) {
      case 'png': return 'image/png';
      case 'webp': return 'image/webp';
      case 'gif': return 'image/gif';
      default: return 'image/jpeg';
    }
  }

  // ── Step execution ───────────────────────────────────────────────────────

  Future<void> _saveCurrentStep() async {
    if (_saving) return;
    setState(() { _saving = true; _stepError = null; });

    try {
      switch (_step) {
        case 0:
          await _saveStep1();
          break;
        case 1:
          await _saveStep2();
          break;
        case 2:
          await _saveStep3();
          break;
        case 3:
          await _saveStep4();
          break;
        case 4:
          await _saveStep5();
          break;
        case 5:
          await _saveStep6();
          break;
        case 6:
          await _saveStep7();
          break;
        case 7:
          await _saveStep8();
          break;
        case 8:
          await _saveStep9();
          break;
        case 9:
          await _runValidation();
          break;
        case 10:
          await _submitPlace();
          return;
      }
      if (mounted && _step < 10) setState(() => _step++);
    } on AdminApiException catch (e) {
      if (mounted) setState(() { _stepError = e.message; _saving = false; });
    } catch (e) {
      if (mounted) setState(() { _stepError = e.toString(); _saving = false; });
    } finally {
      if (mounted && _step <= 9) setState(() => _saving = false);
    }
  }

  Future<void> _saveStep1() async {
    if (_nameCtrl.text.trim().isEmpty) throw AdminApiException(message: 'Name is required');
    if (_selectedCityId == null) throw AdminApiException(message: 'Select a resort city');
    if (_primaryCategorySlug == null) throw AdminApiException(message: 'Select a primary category');

    _place = await widget.apiService.createPlaceDraft(
      name: _nameCtrl.text.trim(),
      cityId: _selectedCityId!,
      primaryCategory: _primaryCategorySlug!,
    );
  }

  Future<void> _saveStep2() async {
    if (_place == null) return;
    if (_descCtrl.text.trim().isEmpty) throw AdminApiException(message: 'Description is required');
    _place = await widget.apiService.updatePlaceBasicInfo(_place!.id, {
      'shortDescription': _shortDescCtrl.text.trim(),
      'description': _descCtrl.text.trim(),
      if (_areaCtrl.text.trim().isNotEmpty) 'area': _areaCtrl.text.trim(),
    });
  }

  Future<void> _saveStep3() async {
    if (_place == null) return;
    final lat = double.tryParse(_latCtrl.text.trim());
    final lng = double.tryParse(_lngCtrl.text.trim());
    _place = await widget.apiService.updatePlaceLocation(_place!.id, {
      if (_addressCtrl.text.trim().isNotEmpty) 'address': _addressCtrl.text.trim(),
      if (lat != null) 'latitude': lat,
      if (lng != null) 'longitude': lng,
      if (_areaCtrl.text.trim().isNotEmpty) 'area': _areaCtrl.text.trim(),
    });
  }

  Future<void> _saveStep4() async {
    if (_place == null) return;
    _place = await widget.apiService.updatePlaceContact(_place!.id, {
      'contact': {
        if (_phoneCtrl.text.trim().isNotEmpty) 'phone': _phoneCtrl.text.trim(),
        if (_emailCtrl.text.trim().isNotEmpty) 'email': _emailCtrl.text.trim(),
        if (_websiteCtrl.text.trim().isNotEmpty) 'website': _websiteCtrl.text.trim(),
      },
    });
  }

  Future<void> _saveStep5() async {
    if (_place == null) return;
    final attributes = <String, dynamic>{};
    if (_isAccommodationType) {
      if (_checkInCtrl.text.isNotEmpty) attributes['checkInTime'] = _checkInCtrl.text.trim();
      if (_checkOutCtrl.text.isNotEmpty) attributes['checkOutTime'] = _checkOutCtrl.text.trim();
      if (_starRatingCtrl.text.isNotEmpty) {
        attributes['starRating'] = int.tryParse(_starRatingCtrl.text) ?? 0;
      }
      final amenities = _amenitiesCtrl.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      if (amenities.isNotEmpty) attributes['generalAmenities'] = amenities;
    } else if (_isDiningType) {
      final cuisines = _cuisineCtrl.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      if (cuisines.isNotEmpty) attributes['cuisine'] = cuisines;
      if (_seatingCapCtrl.text.isNotEmpty) {
        attributes['seatingCapacity'] = int.tryParse(_seatingCapCtrl.text) ?? 0;
      }
      if (_openingHoursCtrl.text.isNotEmpty) attributes['openingHoursNote'] = _openingHoursCtrl.text.trim();
    }
    if (attributes.isNotEmpty) {
      _place = await widget.apiService.updatePlaceAttributes(_place!.id, attributes);
    }
  }

  Future<void> _saveStep6() async {
    if (_place == null) return;
    if (_isAccommodationType && _rooms.isNotEmpty) {
      await widget.apiService.createRooms(_place!.id, _rooms);
    } else if (_isDiningType) {
      if (_menuSections.isNotEmpty) {
        await widget.apiService.createMenuSections(_place!.id, _menuSections);
      }
      if (_menuItems.isNotEmpty) {
        await widget.apiService.createMenuItems(_place!.id, _menuItems);
      }
    } else if (_isEntertainmentType && _shows.isNotEmpty) {
      await widget.apiService.createShows(_place!.id, _shows);
    }
    // Cultural exhibitions skipped for basic wizard — can be added after
  }

  Future<void> _saveStep7() async {
    if (_place == null) return;
    final imageList = _imageUrlCtrls
        .asMap()
        .entries
        .where((e) => e.value.text.trim().isNotEmpty)
        .map((e) => PlaceImage(
              url: e.value.text.trim(),
              isPrimary: e.key == 0,
              order: e.key + 1,
            ).toJson())
        .toList();
    _place = await widget.apiService.updatePlaceMedia(
      _place!.id,
      coverImage: _coverImageCtrl.text.trim().isNotEmpty
          ? _coverImageCtrl.text.trim()
          : null,
      images: imageList,
    );
  }

  Future<void> _saveStep8() async {
    if (_place == null) return;
    _place = await widget.apiService.updatePlaceBooking(_place!.id, {
      'isBookable': _isBookable,
      if (_isBookable) 'pricing': {
        if (_minPriceCtrl.text.isNotEmpty)
          'min': double.tryParse(_minPriceCtrl.text) ?? 0,
        if (_maxPriceCtrl.text.isNotEmpty)
          'max': double.tryParse(_maxPriceCtrl.text) ?? 0,
        'unit': _priceUnit,
        'currency': _currency,
      },
      if (_isBookable) 'bookingSettings': {
        'cancellationPolicy': _cancellationPolicy,
      },
    });
  }

  Future<void> _saveStep9() async {
    if (_place == null) return;
    if (_selectedCategoryIds.isNotEmpty) {
      _place = await widget.apiService.linkPlaceCategories(
          _place!.id, _selectedCategoryIds.toList());
    }
  }

  Future<void> _runValidation() async {
    if (_place == null) return;
    final result = await widget.apiService.validatePlace(_place!.id);
    if (mounted) setState(() { _validationResult = result; _step = 9; });
    if (!result.isValid) {
      throw AdminApiException(message: 'Missing required fields — see below');
    }
  }

  Future<void> _submitPlace() async {
    if (_place == null) return;
    setState(() => _saving = true);
    try {
      final submitted = await widget.apiService.submitPlace(_place!.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('"${submitted.name}" is now ACTIVE'),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
        ));
        Navigator.of(context).pop(true);
      }
    } on AdminApiException catch (e) {
      if (mounted) setState(() { _stepError = e.message; _saving = false; });
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.existingPlace != null
              ? 'Edit Place — ${widget.existingPlace!.name}'
              : 'Add New Place',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_place != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: _PlaceStatusBadge(status: _place!.status),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Progress bar
          _StepProgressBar(currentStep: _step, totalSteps: 11),

          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Step header
                  _StepHeader(step: _step, nestedLabel: _nestedDataLabel),
                  const SizedBox(height: 24),

                  // Error banner
                  if (_stepError != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.error_outline_rounded,
                            color: Colors.redAccent, size: 16),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(_stepError!,
                                style: const TextStyle(color: Colors.redAccent, fontSize: 13))),
                      ]),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Step content
                  _buildStepContent(),
                ],
              ),
            ),
          ),

          // Bottom navigation
          _WizardBottomBar(
            step: _step,
            totalSteps: 11,
            saving: _saving,
            hasPlace: _place != null,
            onBack: _step > 0 ? () => setState(() { _step--; _stepError = null; }) : null,
            onContinue: _saveCurrentStep,
            onSaveExit: _place != null
                ? () => Navigator.of(context).pop(false)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_step) {
      case 0: return _buildStep1();
      case 1: return _buildStep2();
      case 2: return _buildStep3();
      case 3: return _buildStep4();
      case 4: return _buildStep5();
      case 5: return _buildStep6();
      case 6: return _buildStep7();
      case 7: return _buildStep8();
      case 8: return _buildStep9();
      case 9: return _buildStep10();
      case 10: return _buildStep11();
      default: return const SizedBox.shrink();
    }
  }

  // ── Step 1 — Create draft ─────────────────────────────────────────────────
  Widget _buildStep1() {
    // Root categories only as primary category options
    final rootCats = widget.categories.where((c) => c.isRoot).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminField(ctrl: _nameCtrl, label: 'Place Name', hint: 'e.g. Serena Beach Resort & Spa', required: true),

        const SizedBox(height: 4),
        const Text('Resort City',
            style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        _AdminDropdown<String>(
          value: _selectedCityId,
          hint: 'Select the city this place is in',
          items: widget.cities.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
          onChanged: (v) => setState(() => _selectedCityId = v),
        ),
        const SizedBox(height: 16),

        const Text('Primary Category',
            style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        const Text('Used to determine what kind of nested data this place supports.',
            style: TextStyle(color: Colors.white38, fontSize: 11)),
        const SizedBox(height: 8),
        _AdminDropdown<String>(
          value: _primaryCategorySlug,
          hint: 'Select primary category',
          items: rootCats
              .map((c) => DropdownMenuItem(
                    value: c.slug,
                    child: Row(children: [
                      if (c.icon != null)
                        Text(c.icon!, style: const TextStyle(fontSize: 16)),
                      if (c.icon != null) const SizedBox(width: 8),
                      Text(c.name),
                    ]),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _primaryCategorySlug = v),
        ),
      ],
    );
  }

  // ── Step 2 — Basic info ───────────────────────────────────────────────────
  Widget _buildStep2() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminField(ctrl: _shortDescCtrl, label: 'Short Description',
              hint: 'One sentence summary (max 300 chars)', maxLines: 2),
          AdminField(ctrl: _descCtrl, label: 'Full Description',
              hint: 'Detailed description of this place (min 100 chars)',
              maxLines: 5, required: true),
          AdminField(ctrl: _areaCtrl, label: 'Area / Neighbourhood',
              hint: 'e.g. Shanzu, Westlands'),
        ],
      );

  // ── Step 3 — Location ─────────────────────────────────────────────────────
  Widget _buildStep3() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminField(ctrl: _addressCtrl, label: 'Full Address',
              hint: 'e.g. Shanzu Beach Road, Mombasa', maxLines: 2),
          Row(children: [
            Expanded(
              child: AdminField(ctrl: _latCtrl, label: 'Latitude',
                  hint: 'e.g. -3.9875', keyboardType: TextInputType.number),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AdminField(ctrl: _lngCtrl, label: 'Longitude',
                  hint: 'e.g. 39.7392', keyboardType: TextInputType.number),
            ),
          ]),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline_rounded, color: Colors.white38, size: 14),
              SizedBox(width: 8),
              Expanded(child: Text(
                  'Use Google Maps to find accurate coordinates. Right-click any location → "What\'s here?" to see lat/lng.',
                  style: TextStyle(color: Colors.white38, fontSize: 11))),
            ]),
          ),
        ],
      );

  // ── Step 4 — Contact ──────────────────────────────────────────────────────
  Widget _buildStep4() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminField(ctrl: _phoneCtrl, label: 'Phone Number',
              hint: '+254722123456', keyboardType: TextInputType.phone),
          AdminField(ctrl: _emailCtrl, label: 'Email Address',
              hint: 'reservations@example.co.ke', keyboardType: TextInputType.emailAddress),
          AdminField(ctrl: _websiteCtrl, label: 'Website URL',
              hint: 'https://www.example.co.ke', keyboardType: TextInputType.url),
        ],
      );

  // ── Step 5 — Attributes ───────────────────────────────────────────────────
  Widget _buildStep5() {
    if (_isAccommodationType) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: AdminField(ctrl: _checkInCtrl, label: 'Check-in Time', hint: '14:00')),
          const SizedBox(width: 12),
          Expanded(child: AdminField(ctrl: _checkOutCtrl, label: 'Check-out Time', hint: '11:00')),
        ]),
        AdminField(ctrl: _starRatingCtrl, label: 'Star Rating',
            hint: '4', keyboardType: TextInputType.number,
            helperText: 'Enter 1–5'),
        AdminField(ctrl: _amenitiesCtrl, label: 'General Amenities',
            hint: 'Pool, Spa, Restaurant, Beach Access, WiFi',
            helperText: 'Comma-separated list', maxLines: 3),
      ]);
    }
    if (_isDiningType) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AdminField(ctrl: _cuisineCtrl, label: 'Cuisine Types',
            hint: 'Seafood, Italian, Swahili',
            helperText: 'Comma-separated'),
        AdminField(ctrl: _seatingCapCtrl, label: 'Seating Capacity',
            hint: '120', keyboardType: TextInputType.number),
        AdminField(ctrl: _openingHoursCtrl, label: 'Opening Hours',
            hint: 'Mon–Fri: 11:00–23:00, Sat–Sun: 11:00–00:00', maxLines: 2),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AdminField(ctrl: _amenitiesCtrl, label: 'Key Features / Amenities',
          hint: 'Free Parking, WiFi, Accessible',
          helperText: 'Comma-separated list', maxLines: 3),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: const Text(
            'Additional attributes specific to this category type can be added after creation.',
            style: TextStyle(color: Colors.white38, fontSize: 12)),
      ),
    ]);
  }

  // ── Step 6 — Nested data ──────────────────────────────────────────────────
  Widget _buildStep6() {
    if (_isAccommodationType) return _buildRoomsEditor();
    if (_isDiningType) return _buildMenuEditor();
    if (_isEntertainmentType) return _buildShowsEditor();
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(children: [
          const Icon(Icons.layers_outlined, color: Colors.white24, size: 40),
          const SizedBox(height: 12),
          const Text('No nested data for this category type',
              style: TextStyle(color: Colors.white54, fontSize: 14)),
          const SizedBox(height: 8),
          const Text(
              'This step is optional for the selected category. Tap Continue.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
              textAlign: TextAlign.center),
        ]),
      ),
    ]);
  }

  Widget _buildRoomsEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Expanded(child: Text('Rooms',
              style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600))),
          TextButton.icon(
            onPressed: _showAddRoomDialog,
            icon: const Icon(Icons.add_rounded, size: 16, color: Color(0xFF14FFEC)),
            label: const Text('Add Room', style: TextStyle(color: Color(0xFF14FFEC), fontSize: 13)),
          ),
        ]),
        const SizedBox(height: 8),
        if (_rooms.isEmpty)
          _EmptyNestedState(label: 'No rooms added yet', onAdd: _showAddRoomDialog)
        else
          ..._rooms.asMap().entries.map((e) => _NestedItemRow(
                title: e.value['name'] as String? ?? 'Room ${e.key + 1}',
                subtitle: '${e.value['roomType'] ?? ''} · KES ${e.value['basePrice'] ?? 0}',
                onDelete: () => setState(() => _rooms.removeAt(e.key)),
              )),
      ],
    );
  }

  void _showAddRoomDialog() {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final guestsCtrl = TextEditingController(text: '2');
    String roomType = 'DOUBLE';

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(builder: (ctx, setSt) {
        return AlertDialog(
          backgroundColor: const Color(0xFF111827),
          title: const Text('Add Room', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            _SimpleField(ctrl: nameCtrl, label: 'Room Name', hint: 'Deluxe Ocean View Room'),
            const SizedBox(height: 12),
            const Text('Room Type', style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 4),
            _AdminDropdown<String>(
              value: roomType,
              items: ['SINGLE', 'DOUBLE', 'TWIN', 'SUITE', 'FAMILY', 'PENTHOUSE', 'VILLA']
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) => setSt(() => roomType = v ?? 'DOUBLE'),
            ),
            const SizedBox(height: 12),
            _SimpleField(ctrl: guestsCtrl, label: 'Max Guests', hint: '2',
                keyboardType: TextInputType.number),
            _SimpleField(ctrl: priceCtrl, label: 'Base Price (KES)', hint: '15000',
                keyboardType: TextInputType.number),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2196F3)),
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty || priceCtrl.text.trim().isEmpty) return;
                setState(() {
                  _rooms.add({
                    'name': nameCtrl.text.trim(),
                    'roomType': roomType,
                    'maxGuests': int.tryParse(guestsCtrl.text) ?? 2,
                    'maxAdults': int.tryParse(guestsCtrl.text) ?? 2,
                    'maxChildren': 1,
                    'beds': [{'bedType': 'DOUBLE', 'quantity': 1}],
                    'amenities': ['WiFi', 'Air Conditioning'],
                    'basePrice': double.tryParse(priceCtrl.text) ?? 0,
                    'currency': 'KES',
                    'sortOrder': _rooms.length + 1,
                  });
                });
                Navigator.pop(ctx);
              },
              child: const Text('Add Room'),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildMenuEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Expanded(child: Text('Menu Items',
              style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600))),
          TextButton.icon(
            onPressed: _showAddMenuItemDialog,
            icon: const Icon(Icons.add_rounded, size: 16, color: Color(0xFF14FFEC)),
            label: const Text('Add Item', style: TextStyle(color: Color(0xFF14FFEC), fontSize: 13)),
          ),
        ]),
        const SizedBox(height: 8),
        if (_menuItems.isEmpty)
          _EmptyNestedState(label: 'No menu items added yet', onAdd: _showAddMenuItemDialog)
        else
          ..._menuItems.asMap().entries.map((e) => _NestedItemRow(
                title: e.value['name'] as String? ?? 'Item ${e.key + 1}',
                subtitle: '${e.value['mealType'] ?? ''} · KES ${e.value['price'] ?? 0}',
                onDelete: () => setState(() => _menuItems.removeAt(e.key)),
              )),
      ],
    );
  }

  void _showAddMenuItemDialog() {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    String mealType = 'LUNCH';

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(builder: (ctx, setSt) {
        return AlertDialog(
          backgroundColor: const Color(0xFF111827),
          title: const Text('Add Menu Item', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            _SimpleField(ctrl: nameCtrl, label: 'Item Name', hint: 'Grilled Lobster'),
            const SizedBox(height: 12),
            const Text('Meal Type', style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 4),
            _AdminDropdown<String>(
              value: mealType,
              items: ['BREAKFAST', 'LUNCH', 'DINNER', 'BRUNCH', 'SNACK', 'DESSERT', 'BEVERAGE']
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) => setSt(() => mealType = v ?? 'LUNCH'),
            ),
            const SizedBox(height: 12),
            _SimpleField(ctrl: priceCtrl, label: 'Price (KES)', hint: '1500',
                keyboardType: TextInputType.number),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF50057)),
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty || priceCtrl.text.trim().isEmpty) return;
                setState(() {
                  _menuItems.add({
                    'name': nameCtrl.text.trim(),
                    'mealType': mealType,
                    'price': double.tryParse(priceCtrl.text) ?? 0,
                    'currency': 'KES',
                    'isAvailable': true,
                    'sortOrder': _menuItems.length + 1,
                  });
                });
                Navigator.pop(ctx);
              },
              child: const Text('Add Item'),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildShowsEditor() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Expanded(child: Text('Shows / Events',
                style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600))),
            TextButton.icon(
              onPressed: () => setState(() => _shows.add({
                    'name': 'New Show',
                    'category': 'CONCERT',
                    'durationMinutes': 90,
                    'ticketPricing': {'standard': 1000},
                  })),
              icon: const Icon(Icons.add_rounded, size: 16, color: Color(0xFF14FFEC)),
              label: const Text('Add Show', style: TextStyle(color: Color(0xFF14FFEC), fontSize: 13)),
            ),
          ]),
          if (_shows.isEmpty)
            _EmptyNestedState(label: 'No shows added', onAdd: null)
          else
            ..._shows.asMap().entries.map((e) => _NestedItemRow(
                  title: e.value['name'] as String? ?? 'Show ${e.key + 1}',
                  subtitle: '${e.value['category'] ?? ''} · ${e.value['durationMinutes']} min',
                  onDelete: () => setState(() => _shows.removeAt(e.key)),
                )),
        ],
      );

  // ── Step 7 — Media ────────────────────────────────────────────────────────
  Widget _buildStep7() {
    final anyUploading = _uploadingCover || _galleryUploading.any((v) => v);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Cover Image ──────────────────────────────────────────────────
        const Text('Cover Image',
            style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        const Text(
            'Main image shown on place cards. Upload a photo or paste a URL.',
            style: TextStyle(color: Colors.white38, fontSize: 11)),
        const SizedBox(height: 10),

        // Preview + upload zone
        _ImageUploadTile(
          imageBytes: _coverImageBytes,
          existingUrl: _coverImageCtrl.text,
          uploading: _uploadingCover,
          uploadProgress: _coverUploadProgress,
          label: 'Cover Photo',
          onPickTap: (_saving || anyUploading) ? null : _pickAndUploadCoverImage,
        ),

        const SizedBox(height: 8),

        // URL field — autofilled after upload; editable as fallback
        _SimpleField(
          ctrl: _coverImageCtrl,
          label: 'Cover Image URL',
          hint: 'Auto-filled after upload — or paste a URL directly',
          keyboardType: TextInputType.url,
        ),

        const SizedBox(height: 20),

        // ── Gallery Images ───────────────────────────────────────────────
        const Text('Gallery Images',
            style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        const Text(
            'Upload additional photos — the first slot is the primary gallery image.',
            style: TextStyle(color: Colors.white38, fontSize: 11)),
        const SizedBox(height: 10),

        // Gallery slots
        ..._imageUrlCtrls.asMap().entries.map((entry) {
          final i = entry.key;
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      i == 0 ? 'Image 1 — Primary' : 'Image ${i + 1}',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12),
                    ),
                    const Spacer(),
                    // Remove button — only shown when more than one slot
                    if (_imageUrlCtrls.length > 1)
                      GestureDetector(
                        onTap: (_saving || _galleryUploading[i])
                            ? null
                            : () => _removeGallerySlot(i),
                        child: const Icon(Icons.remove_circle_rounded,
                            color: Colors.redAccent, size: 18),
                      ),
                  ],
                ),
                const SizedBox(height: 6),

                _ImageUploadTile(
                  imageBytes: _galleryBytes[i],
                  existingUrl: _imageUrlCtrls[i].text,
                  uploading: _galleryUploading[i],
                  uploadProgress: _galleryProgress[i],
                  label: i == 0 ? 'Primary Gallery Photo' : 'Gallery Photo ${i + 1}',
                  onPickTap: (_saving || anyUploading)
                      ? null
                      : () => _pickAndUploadGalleryImage(i),
                ),

                const SizedBox(height: 6),

                _SimpleField(
                  ctrl: _imageUrlCtrls[i],
                  label: 'Image URL',
                  hint: 'Auto-filled after upload — or paste a URL directly',
                  keyboardType: TextInputType.url,
                ),
              ],
            ),
          );
        }),

        // Add another slot
        TextButton.icon(
          onPressed: (_saving || anyUploading) ? null : _addGallerySlot,
          icon: Icon(
            Icons.add_photo_alternate_outlined,
            size: 16,
            color: (_saving || anyUploading)
                ? Colors.white24
                : const Color(0xFF14FFEC),
          ),
          label: Text(
            'Add another image',
            style: TextStyle(
              fontSize: 13,
              color: (_saving || anyUploading)
                  ? Colors.white24
                  : const Color(0xFF14FFEC),
            ),
          ),
        ),
      ],
    );
  }

  // ── Step 8 — Booking ──────────────────────────────────────────────────────
  Widget _buildStep8() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Expanded(child: Text('Enable Booking',
                style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500))),
            Switch(
              value: _isBookable,
              activeThumbColor: Colors.greenAccent,
              onChanged: (v) => setState(() => _isBookable = v),
            ),
          ]),
          if (_isBookable) ...[
            const Divider(color: Colors.white12, height: 24),
            const Text('Pricing',
                style: TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 1)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: AdminField(ctrl: _minPriceCtrl, label: 'Min Price',
                  hint: '5000', keyboardType: TextInputType.number)),
              const SizedBox(width: 12),
              Expanded(child: AdminField(ctrl: _maxPriceCtrl, label: 'Max Price',
                  hint: '50000', keyboardType: TextInputType.number)),
            ]),
            Row(children: [
              Expanded(child: _LabeledDropdown(
                label: 'Price Unit',
                value: _priceUnit,
                items: const ['night', 'hour', 'person', 'session'],
                onChanged: (v) => setState(() => _priceUnit = v ?? 'night'),
              )),
              const SizedBox(width: 12),
              Expanded(child: _LabeledDropdown(
                label: 'Currency',
                value: _currency,
                items: const ['KES', 'USD', 'EUR', 'GBP'],
                onChanged: (v) => setState(() => _currency = v ?? 'KES'),
              )),
            ]),
            const SizedBox(height: 8),
            _LabeledDropdown(
              label: 'Cancellation Policy',
              value: _cancellationPolicy,
              items: const ['flexible', 'moderate', 'strict'],
              onChanged: (v) => setState(() => _cancellationPolicy = v ?? 'flexible'),
            ),
          ],
        ],
      );

  // ── Step 9 — Categories multi-select ─────────────────────────────────────
  Widget _buildStep9() {
    final roots = widget.categories.where((c) => c.isRoot).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0D1117),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF2196F3).withValues(alpha: 0.3)),
          ),
          child: const Row(children: [
            Icon(Icons.info_outline_rounded, color: Color(0xFF2196F3), size: 14),
            SizedBox(width: 8),
            Expanded(child: Text(
                'Select every category this place offers. A hotel that offers accommodation AND dining AND wellness should have all three selected.',
                style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4))),
          ]),
        ),
        const SizedBox(height: 20),

        ...roots.map((root) {
          final childrenOfRoot = widget.categories
              .where((c) => c.parentId == root.id)
              .toList();
          final allIds = [root.id, ...childrenOfRoot.map((c) => c.id)];
          final anySelected = allIds.any((id) => _selectedCategoryIds.contains(id));

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: anySelected
                      ? const Color(0xFF2196F3).withValues(alpha: 0.4)
                      : Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Root category toggle
                Row(children: [
                  if (root.icon != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(root.icon!, style: const TextStyle(fontSize: 16)),
                    ),
                  Expanded(
                    child: Text(root.name,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                  ),
                  Checkbox(
                    value: _selectedCategoryIds.contains(root.id),
                    activeColor: const Color(0xFF2196F3),
                    checkColor: Colors.white,
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selectedCategoryIds.add(root.id);
                      } else {
                        _selectedCategoryIds.remove(root.id);
                      }
                    }),
                  ),
                ]),
                // Child categories
                if (childrenOfRoot.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  ...childrenOfRoot.map((child) => Row(children: [
                        const SizedBox(width: 24),
                        const Icon(Icons.subdirectory_arrow_right_rounded,
                            color: Colors.white24, size: 14),
                        const SizedBox(width: 4),
                        Expanded(
                            child: Text(child.name,
                                style: const TextStyle(color: Colors.white54, fontSize: 13))),
                        Checkbox(
                          value: _selectedCategoryIds.contains(child.id),
                          activeColor: const Color(0xFF2196F3),
                          checkColor: Colors.white,
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              _selectedCategoryIds.add(child.id);
                            } else {
                              _selectedCategoryIds.remove(child.id);
                            }
                          }),
                        ),
                      ])),
                ],
              ],
            ),
          );
        }),

        if (_selectedCategoryIds.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('${_selectedCategoryIds.length} categor${_selectedCategoryIds.length == 1 ? 'y' : 'ies'} selected',
              style: const TextStyle(color: Color(0xFF14FFEC), fontSize: 12)),
        ],
      ],
    );
  }

  // ── Step 10 — Validate ───────────────────────────────────────────────────
  Widget _buildStep10() {
    if (_validationResult == null) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF14FFEC)));
    }
    final result = _validationResult!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: result.isValid
                ? Colors.green.withValues(alpha: 0.1)
                : Colors.orange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: result.isValid
                    ? Colors.greenAccent.withValues(alpha: 0.35)
                    : Colors.orangeAccent.withValues(alpha: 0.35)),
          ),
          child: Row(children: [
            Icon(
              result.isValid
                  ? Icons.check_circle_rounded
                  : Icons.warning_amber_rounded,
              color: result.isValid ? Colors.greenAccent : Colors.orangeAccent,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                result.isValid
                    ? 'All required fields are complete. Ready to submit!'
                    : 'Some required fields are missing. Go back and complete them.',
                style: TextStyle(
                    color: result.isValid ? Colors.greenAccent : Colors.orangeAccent,
                    fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
          ]),
        ),
        if (result.missing.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('Missing fields:',
              style: TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 1)),
          const SizedBox(height: 8),
          ...result.missing.map((m) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  const Icon(Icons.remove_circle_outline_rounded,
                      color: Colors.orangeAccent, size: 14),
                  const SizedBox(width: 8),
                  Text(m,
                      style: const TextStyle(color: Colors.white60, fontSize: 13)),
                ]),
              )),
        ],
      ],
    );
  }

  // ── Step 11 — Submit ─────────────────────────────────────────────────────
  Widget _buildStep11() => Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(children: [
              const Icon(Icons.rocket_launch_rounded,
                  color: Color(0xFF14FFEC), size: 48),
              const SizedBox(height: 16),
              Text(_place?.name ?? '',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text(
                  'Tapping "Submit & Activate" will change this place from PENDING to ACTIVE, making it visible in the user-facing app.',
                  style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.5),
                  textAlign: TextAlign.center),
              if (_place != null) ...[
                const SizedBox(height: 20),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _SummaryPill(
                      icon: Icons.location_on_rounded,
                      label: _place!.cityName.isNotEmpty ? _place!.cityName : 'City set'),
                  const SizedBox(width: 8),
                  _SummaryPill(
                      icon: Icons.category_rounded,
                      label: '${_selectedCategoryIds.length} categories'),
                  const SizedBox(width: 8),
                  _SummaryPill(
                      icon: Icons.photo_rounded,
                      label: _place!.hasMedia ? 'Has media' : 'No media'),
                ]),
              ],
            ]),
          ),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Wizard sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _StepProgressBar extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  const _StepProgressBar({required this.currentStep, required this.totalSteps});

  @override
  Widget build(BuildContext context) {
    final labels = ['Draft', 'Info', 'Location', 'Contact', 'Attrs', 'Data',
        'Media', 'Booking', 'Categories', 'Validate', 'Submit'];
    return Container(
      color: const Color(0xFF111827),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(children: [
        Row(
          children: List.generate(totalSteps, (i) {
            final isDone = i < currentStep;
            final isCurrent = i == currentStep;
            return Expanded(child: Row(children: [
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: 3,
                  decoration: BoxDecoration(
                    color: isDone || isCurrent
                        ? const Color(0xFF14FFEC)
                        : Colors.white12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              if (i < totalSteps - 1) const SizedBox(width: 2),
            ]));
          }),
        ),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Step ${currentStep + 1} of $totalSteps',
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
          Text(labels[currentStep],
              style: const TextStyle(
                  color: Color(0xFF14FFEC), fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
      ]),
    );
  }
}

class _StepHeader extends StatelessWidget {
  final int step;
  final String nestedLabel;
  const _StepHeader({required this.step, required this.nestedLabel});

  static const _titles = [
    'Create Draft', 'Basic Information', 'Location', 'Contact Details',
    'Attributes', '', 'Media & Images', 'Booking & Pricing',
    'Link Categories', 'Validate', 'Submit & Activate'
  ];
  static const _subs = [
    'Set the name, city, and primary category',
    'Add a description and area information',
    'Set address and GPS coordinates',
    'Add phone, email, and website',
    'Add category-specific details',
    '',
    'Add cover photo and gallery images',
    'Configure pricing and booking options',
    'Select all applicable service categories',
    'Check required fields are complete',
    'Make this place live in the app'
  ];

  @override
  Widget build(BuildContext context) {
    final title = step == 5 ? nestedLabel : _titles[step];
    final sub = step == 5 ? 'Add ${nestedLabel.toLowerCase()} for this place (optional)' : _subs[step];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title,
          style: const TextStyle(
              color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      Text(sub, style: const TextStyle(color: Colors.white38, fontSize: 13)),
    ]);
  }
}

class _WizardBottomBar extends StatelessWidget {
  final int step;
  final int totalSteps;
  final bool saving;
  final bool hasPlace;
  final VoidCallback? onBack;
  final VoidCallback onContinue;
  final VoidCallback? onSaveExit;

  const _WizardBottomBar({
    required this.step, required this.totalSteps, required this.saving,
    required this.hasPlace, this.onBack, required this.onContinue, this.onSaveExit,
  });

  @override
  Widget build(BuildContext context) {
    final isLast = step == totalSteps - 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.07))),
      ),
      child: Row(children: [
        if (onBack != null)
          OutlinedButton.icon(
            onPressed: saving ? null : onBack,
            icon: const Icon(Icons.arrow_back_rounded, size: 16),
            label: const Text('Back'),
            style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white54,
                side: const BorderSide(color: Colors.white24),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
          ),
        if (onSaveExit != null) ...[
          const SizedBox(width: 8),
          TextButton(
            onPressed: saving ? null : onSaveExit,
            child: const Text('Save & Exit', style: TextStyle(color: Colors.white38)),
          ),
        ],
        const Spacer(),
        ElevatedButton.icon(
          onPressed: saving ? null : onContinue,
          icon: saving
              ? const SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Icon(isLast ? Icons.rocket_launch_rounded : Icons.arrow_forward_rounded,
                  size: 16),
          label: Text(saving
              ? 'Saving…'
              : isLast ? 'Submit & Activate' : 'Save & Continue'),
          style: ElevatedButton.styleFrom(
            backgroundColor: isLast ? Colors.greenAccent.shade700 : const Color(0xFF14FFEC),
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ]),
    );
  }
}

class _AdminDropdown<T> extends StatelessWidget {
  final T? value;
  final String? hint;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _AdminDropdown({this.value, this.hint, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1117),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12),
        ),
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: const Color(0xFF1F2937),
          style: const TextStyle(color: Colors.white70, fontSize: 14),
          underline: const SizedBox.shrink(),
          hint: hint != null
              ? Text(hint!, style: const TextStyle(color: Colors.white24, fontSize: 13))
              : null,
          onChanged: onChanged,
          items: items,
        ),
      );
}

class _LabeledDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  const _LabeledDropdown({required this.label, required this.value,
      required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          _AdminDropdown<String>(
            value: value,
            items: items.map((i) => DropdownMenuItem(value: i, child: Text(i))).toList(),
            onChanged: onChanged,
          ),
          const SizedBox(height: 16),
        ],
      );
}

class _SimpleField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final String hint;
  final TextInputType? keyboardType;
  const _SimpleField({required this.ctrl, required this.label, required this.hint,
      this.keyboardType});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 6),
          TextFormField(
            controller: ctrl,
            keyboardType: keyboardType,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
              filled: true,
              fillColor: const Color(0xFF0D1117),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.white12)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.white12)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF14FFEC))),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),
        ],
      );
}

class _NestedItemRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onDelete;
  const _NestedItemRow({required this.title, required this.subtitle, required this.onDelete});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1117),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(children: [
          const Icon(Icons.drag_handle_rounded, color: Colors.white24, size: 16),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ])),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 16),
            onPressed: onDelete,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ]),
      );
}

class _EmptyNestedState extends StatelessWidget {
  final String label;
  final VoidCallback? onAdd;
  const _EmptyNestedState({required this.label, this.onAdd});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12, style: BorderStyle.solid),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 13)),
          if (onAdd != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: onAdd,
              child: const Text('+ Add one now', style: TextStyle(color: Color(0xFF14FFEC), fontSize: 13)),
            ),
          ],
        ]),
      );
}

class _PlaceStatusBadge extends StatelessWidget {
  final String status;
  const _PlaceStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status) {
      case 'ACTIVE': color = Colors.greenAccent; break;
      case 'SUSPENDED': color = Colors.orangeAccent; break;
      case 'ARCHIVED': color = Colors.grey; break;
      default: color = Colors.blueAccent; // PENDING
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(status,
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

class _SummaryPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SummaryPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: const Color(0xFF14FFEC)),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// _ImageUploadTile
//
// Reusable upload tile used by both the cover image and each gallery slot in
// Step 7. Renders a 16:9 image preview (from bytes or URL), an upload progress
// bar while uploading, and a pick/change button when idle.
// ─────────────────────────────────────────────────────────────────────────────

class _ImageUploadTile extends StatelessWidget {
  final Uint8List? imageBytes;
  final String existingUrl;
  final bool uploading;
  final double uploadProgress;
  final String label;
  final VoidCallback? onPickTap;

  const _ImageUploadTile({
    required this.imageBytes,
    required this.existingUrl,
    required this.uploading,
    required this.uploadProgress,
    required this.label,
    required this.onPickTap,
  });

  bool get _hasPreview =>
      imageBytes != null || existingUrl.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: uploading
              ? const Color(0xFF14FFEC).withValues(alpha: 0.4)
              : Colors.white12,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 16:9 preview ──────────────────────────────────────────────
          if (_hasPreview)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: _buildPreview(),
            ),

          // ── Upload progress ───────────────────────────────────────────
          if (uploading)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: uploadProgress,
                      minHeight: 5,
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation(Color(0xFF14FFEC)),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Uploading… ${(uploadProgress * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),

          // ── Pick / change button ──────────────────────────────────────
          if (!uploading)
            Padding(
              padding: const EdgeInsets.all(8),
              child: OutlinedButton.icon(
                onPressed: onPickTap,
                icon: Icon(
                  _hasPreview
                      ? Icons.change_circle_rounded
                      : Icons.upload_file_rounded,
                  size: 15,
                  color: onPickTap != null
                      ? const Color(0xFF14FFEC)
                      : Colors.white24,
                ),
                label: Text(
                  _hasPreview ? 'Change $label' : 'Upload $label',
                  style: TextStyle(
                    fontSize: 12,
                    color: onPickTap != null
                        ? const Color(0xFF14FFEC)
                        : Colors.white24,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  side: BorderSide(
                    color: onPickTap != null
                        ? const Color(0xFF14FFEC).withValues(alpha: 0.5)
                        : Colors.white12,
                  ),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7)),
                ),
              ),
            ),

          if (uploading) const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    if (imageBytes != null) {
      return Image.memory(
        imageBytes!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }
    if (existingUrl.trim().isNotEmpty) {
      return Image.network(
        existingUrl.trim(),
        fit: BoxFit.cover,
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : Container(
                color: Colors.white.withValues(alpha: 0.03),
                child: Center(
                  child: CircularProgressIndicator(
                    value: progress.expectedTotalBytes != null
                        ? progress.cumulativeBytesLoaded /
                            progress.expectedTotalBytes!
                        : null,
                    color: const Color(0xFF14FFEC),
                    strokeWidth: 2,
                  ),
                ),
              ),
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _placeholder() => Container(
        color: Colors.white.withValues(alpha: 0.03),
        child: const Center(
          child: Icon(Icons.broken_image_rounded,
              color: Colors.white24, size: 36),
        ),
      );
}