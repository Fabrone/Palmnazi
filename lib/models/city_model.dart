// ─────────────────────────────────────────────────────────────────────────────
// city_model.dart
//
// Data-transfer model that mirrors the backend's resort-city JSON shape
// exactly.  This is intentionally kept separate from the display-focused
// [ResortCityItem] in models.dart so that API contract changes do not
// accidentally break the existing UI layer.
//
// Backend response shape (from POST /api/cities, GET /api/cities, etc.):
// {
//   "id":          "c123",
//   "name":        "Nairobi",
//   "slug":        "nairobi",
//   "country":     "Kenya",
//   "region":      "Nairobi",
//   "latitude":    -1.2921,
//   "longitude":   36.8219,
//   "coverImage":  "https://example.com/image.jpg",
//   "description": "Capital city of Kenya",
//   "isActive":    true,
//   "totalPlaces": 120,
//   "totalEvents": 15,
//   "categoryCounts": { "dining": 50, "accommodation": 70 },
//   "createdAt":   "2026-02-09T12:00:00.000Z",
//   "updatedAt":   "2026-02-09T12:00:00.000Z"
// }
// ─────────────────────────────────────────────────────────────────────────────

class CityModel {
  final String id;
  final String name;
  final String slug;
  final String country;
  final String region;
  final double latitude;
  final double longitude;
  final String coverImage;
  final String description;
  final bool isActive;
  final int totalPlaces;
  final int totalEvents;
  final Map<String, int>? categoryCounts;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CityModel({
    required this.id,
    required this.name,
    required this.slug,
    required this.country,
    required this.region,
    required this.latitude,
    required this.longitude,
    required this.coverImage,
    required this.description,
    required this.isActive,
    this.totalPlaces = 0,
    this.totalEvents = 0,
    this.categoryCounts,
    required this.createdAt,
    required this.updatedAt,
  });

  // ── Deserialization ────────────────────────────────────────────────────────

  factory CityModel.fromJson(Map<String, dynamic> json) {
    // categoryCounts arrives as Map<String, dynamic> — cast safely
    Map<String, int>? counts;
    final raw = json['categoryCounts'];
    if (raw is Map) {
      // Guard against null or non-numeric values from a malformed response.
      // The API guarantees integers here, but a defensive cast avoids a
      // hard-crash if the backend ever sends unexpected data for a key.
      counts = raw.map(
        (k, v) => MapEntry(k.toString(), v is num ? v.toInt() : 0),
      );
    }

    return CityModel(
      id:          json['id'] as String,
      name:        json['name'] as String,
      slug:        json['slug'] as String? ?? '',
      country:     json['country'] as String? ?? '',
      region:      json['region'] as String? ?? '',
      latitude:    (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude:   (json['longitude'] as num?)?.toDouble() ?? 0.0,
      coverImage:  json['coverImage'] as String? ?? '',
      description: json['description'] as String? ?? '',
      isActive:    json['isActive'] as bool? ?? true,
      totalPlaces: (json['totalPlaces'] as num?)?.toInt() ?? 0,
      totalEvents: (json['totalEvents'] as num?)?.toInt() ?? 0,
      categoryCounts: counts,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  // ── Serialization (POST / PUT request body) ────────────────────────────────

  /// Returns the fields the backend accepts for CREATE (POST /api/cities).
  ///
  /// [coverImage] is omitted when empty so the backend does not receive an
  /// empty-string URL that may fail URL validation on creation.
  Map<String, dynamic> toCreateJson() => {
        'name':        name,
        'country':     country,
        'region':      region,
        'slug':        slug,
        'latitude':    latitude,
        'longitude':   longitude,
        if (coverImage.isNotEmpty) 'coverImage': coverImage,
        'description': description,
        'isActive':    isActive,
      };

  /// Returns the writable fields for a partial UPDATE (PUT /api/cities/:id).
  ///
  /// Every scalar field is always included, even when empty/zero, so that an
  /// admin can intentionally clear a value (e.g. remove a cover image or
  /// description).  The backend treats missing fields as "leave unchanged", so
  /// omitting a field makes it impossible to clear — which is why all fields
  /// must be sent unconditionally here.
  ///
  /// IMPORTANT: [latitude] and [longitude] must NOT be filtered by `!= 0.0`.
  /// Zero is a perfectly valid coordinate (Gulf of Guinea / prime meridian).
  /// Using 0.0 as a sentinel would silently drop real coordinates on update.
  Map<String, dynamic> toUpdateJson() => {
        'name':        name,
        'country':     country,
        'region':      region,
        'slug':        slug,
        'latitude':    latitude,
        'longitude':   longitude,
        'coverImage':  coverImage,
        'description': description,
        'isActive':    isActive,
      };

  // ── Copy-with for in-memory edits ─────────────────────────────────────────

  CityModel copyWith({
    String? id,
    String? name,
    String? slug,
    String? country,
    String? region,
    double? latitude,
    double? longitude,
    String? coverImage,
    String? description,
    bool? isActive,
    int? totalPlaces,
    int? totalEvents,
    Map<String, int>? categoryCounts,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      CityModel(
        id:             id          ?? this.id,
        name:           name        ?? this.name,
        slug:           slug        ?? this.slug,
        country:        country     ?? this.country,
        region:         region      ?? this.region,
        latitude:       latitude    ?? this.latitude,
        longitude:      longitude   ?? this.longitude,
        coverImage:     coverImage  ?? this.coverImage,
        description:    description ?? this.description,
        isActive:       isActive    ?? this.isActive,
        totalPlaces:    totalPlaces ?? this.totalPlaces,
        totalEvents:    totalEvents ?? this.totalEvents,
        categoryCounts: categoryCounts ?? this.categoryCounts,
        createdAt:      createdAt   ?? this.createdAt,
        updatedAt:      updatedAt   ?? this.updatedAt,
      );

  @override
  String toString() =>
      'CityModel(id: $id, name: $name, slug: $slug, isActive: $isActive)';
}