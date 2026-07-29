import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CategoryDetailsModel
//
// Firestore collection : CategoryDetails
// Document ID          : the category's /api/categories id (one doc per
//                         category).
//
// Extends a channel/category beyond the /api/categories contract: which
// resort cities it's scoped to (empty = all cities, matching today's
// behaviour) and free-form tags for search/filtering. Same pattern as
// CityDetailsModel — the backend REST contract is frozen.
// ─────────────────────────────────────────────────────────────────────────────

class CategoryDetailsModel {
  final String categoryId;
  final List<String> cityIds; // empty = visible in every resort city
  final List<String> tags;

  const CategoryDetailsModel({
    required this.categoryId,
    this.cityIds = const [],
    this.tags = const [],
  });

  bool get isScopedToAllCities => cityIds.isEmpty;
  bool appliesTo(String cityId) => cityIds.isEmpty || cityIds.contains(cityId);

  factory CategoryDetailsModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return CategoryDetailsModel(
      categoryId: doc.id,
      cityIds:
          (d['cityIds'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
              const [],
      tags: (d['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
          const [],
    );
  }

  static const empty = CategoryDetailsModel(categoryId: '');
}
