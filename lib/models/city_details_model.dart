import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CityDetailsModel
//
// Firestore collection : City_details
// Document ID          : the city's /api/cities id (one doc per city).
//
// Presentation configuration for a resort city that isn't part of the
// /api/cities contract: whether it should be featured/pinned first, and its
// manual display order relative to other cities. Both the admin dashboard's
// Resort Cities list and the tourist-facing landing page sort by this data.
// ─────────────────────────────────────────────────────────────────────────────

class CityDetailsModel {
  final String cityId;
  final bool featured;
  final int sortOrder;

  const CityDetailsModel({
    required this.cityId,
    this.featured = false,
    this.sortOrder = 0,
  });

  factory CityDetailsModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return CityDetailsModel(
      cityId: doc.id,
      featured: d['featured'] as bool? ?? false,
      sortOrder: (d['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }

  static const empty = CityDetailsModel(cityId: '');
}
