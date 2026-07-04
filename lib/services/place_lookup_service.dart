import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:palmnazi/models/place_model.dart';
import 'package:palmnazi/services/api_client.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PlaceLookupService
//
// Public (no auth token required) single-place fetch, shared by
// place_details_screen.dart (upgrading its lean list model to the full
// detail record) and my_favorites_screen.dart (resolving a favorited place
// snapshot back to a full PlaceModel before navigating to its details page).
// ─────────────────────────────────────────────────────────────────────────────

class PlaceLookupService {
  PlaceLookupService._();

  static const _timeout = Duration(seconds: 15);

  /// GET /api/places/:id?includeAttributes=true
  ///
  /// Returns the full place detail object including contact, description,
  /// attributes, images, bookingSettings, and categoryLinks.
  /// Returns null on any non-200 response or parse failure.
  static Future<PlaceModel?> fetchPlace(String placeId) async {
    final uri = Uri.parse(
      ApiEndpoints.url('/api/places/$placeId?includeAttributes=true'),
    );
    try {
      final resp = await http.get(uri).timeout(_timeout);
      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final data = body['data'];
      if (data is Map<String, dynamic>) {
        return PlaceModel.fromJson(data);
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
