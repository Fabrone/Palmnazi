// ─────────────────────────────────────────────────────────────────────────────
// PlaceModel
//
// Maps to the backend /api/places response shape.
// All fields beyond id/name/cityId/status are nullable because a place
// is built progressively over 11 steps — the object exists in PENDING state
// from step 1, with fields filled in as the admin advances through the wizard.
// ─────────────────────────────────────────────────────────────────────────────

class PlaceModel {
  final String id;
  final String name;
  final String slug;
  final String? shortDescription;
  final String? description;
  final String cityId;
  final Map<String, dynamic>? city;
  final String? address;
  final double? latitude;
  final double? longitude;
  final String? area;
  final PlaceContact? contact;
  final String? coverImage;
  final List<PlaceImage> images;
  final List<String> taxonomy;
  final Map<String, dynamic> attributes;
  final bool isBookable;
  final PlacePricing? pricing;
  final PlaceBookingSettings? bookingSettings;
  final List<PlaceCategoryLink> categoryLinks;
  final String status;
  final int? verificationLevel;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const PlaceModel({
    required this.id,
    required this.name,
    required this.slug,
    this.shortDescription,
    this.description,
    required this.cityId,
    this.city,
    this.address,
    this.latitude,
    this.longitude,
    this.area,
    this.contact,
    this.coverImage,
    this.images = const [],
    this.taxonomy = const [],
    this.attributes = const {},
    this.isBookable = false,
    this.pricing,
    this.bookingSettings,
    this.categoryLinks = const [],
    required this.status,
    this.verificationLevel,
    this.createdAt,
    this.updatedAt,
  });

  bool get isDraft => status == 'PENDING';
  bool get isActive => status == 'ACTIVE';
  bool get isSuspended => status == 'SUSPENDED';
  bool get isArchived => status == 'ARCHIVED';

  String get cityName => (city?['name'] as String?) ?? '';

  List<String> get categoryNames =>
      categoryLinks.map((l) => l.categoryName).toList();

  bool get hasLocation => latitude != null && longitude != null;
  bool get hasContact => contact != null;
  bool get hasMedia => coverImage != null || images.isNotEmpty;
  bool get hasCategories => categoryLinks.isNotEmpty;
  bool get hasDescription => description != null && description!.isNotEmpty;

  // Returns 0-100 progress of how complete the place setup is.
  //
  // SHORT-CIRCUIT: The backend's submit endpoint runs full validation before
  // transitioning a place to ACTIVE — it cannot become ACTIVE with any required
  // field missing.  The list endpoint (GET /api/places) returns lean payloads
  // that omit description, contact, and attributes, so scoring those fields on
  // a lean model always shows < 100% even for a fully complete place.
  // Rather than requiring includeAttributes=true for every list call, we treat
  // ACTIVE status as the authoritative signal that all steps are done.
  int get completionPercent {
    if (isActive) return 100;
    int completed = 0;
    if (hasDescription) completed += 20;
    if (hasLocation) completed += 15;
    if (hasContact) completed += 15;
    if (attributes.isNotEmpty) completed += 10;
    if (hasMedia) completed += 15;
    if (isBookable || pricing != null) completed += 10;
    if (hasCategories) completed += 15;
    return completed;
  }

  factory PlaceModel.fromJson(Map<String, dynamic> json) {
    return PlaceModel(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String? ?? '',
      shortDescription: json['shortDescription'] as String?,
      description: json['description'] as String?,
      cityId: json['cityId'] as String? ?? '',
      city: json['city'] as Map<String, dynamic>?,
      address: json['address'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      area: json['area'] as String?,
      contact: json['contact'] != null
          ? PlaceContact.fromJson(json['contact'] as Map<String, dynamic>)
          : null,
      coverImage: json['coverImage'] as String?,
      images: (json['images'] as List<dynamic>?)
              ?.map((i) => PlaceImage.fromJson(i as Map<String, dynamic>))
              .toList() ??
          [],
      taxonomy: (json['taxonomy'] as List<dynamic>?)
              ?.map((t) => t.toString())
              .toList() ??
          [],
      attributes: (json['attributes'] as Map<String, dynamic>?) ?? {},
      isBookable: json['isBookable'] as bool? ?? false,
      pricing: json['pricing'] != null
          ? PlacePricing.fromJson(json['pricing'] as Map<String, dynamic>)
          : null,
      bookingSettings: json['bookingSettings'] != null
          ? PlaceBookingSettings.fromJson(
              json['bookingSettings'] as Map<String, dynamic>)
          : null,
      categoryLinks: (json['categoryLinks'] as List<dynamic>?)
              ?.map((l) => PlaceCategoryLink.fromJson(l as Map<String, dynamic>))
              .toList() ??
          [],
      status: json['status'] as String? ?? 'PENDING',
      verificationLevel: json['verificationLevel'] as int?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String)
          : null,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Nested value types
// ─────────────────────────────────────────────────────────────────────────────

class PlaceContact {
  final String? phone;
  final String? email;
  final String? website;

  const PlaceContact({this.phone, this.email, this.website});

  factory PlaceContact.fromJson(Map<String, dynamic> json) => PlaceContact(
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        website: json['website'] as String?,
      );

  Map<String, dynamic> toJson() => {
        if (phone != null) 'phone': phone,
        if (email != null) 'email': email,
        if (website != null) 'website': website,
      };
}

class PlaceImage {
  final String url;
  final String? caption;
  final bool isPrimary;
  final int order;

  const PlaceImage({
    required this.url,
    this.caption,
    this.isPrimary = false,
    this.order = 0,
  });

  factory PlaceImage.fromJson(Map<String, dynamic> json) => PlaceImage(
        url: json['url'] as String,
        caption: json['caption'] as String?,
        isPrimary: json['isPrimary'] as bool? ?? false,
        order: (json['order'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'url': url,
        if (caption != null) 'caption': caption,
        'isPrimary': isPrimary,
        'order': order,
      };
}

class PlacePricing {
  final double? min;
  final double? max;
  final String unit;
  final String currency;

  const PlacePricing({
    this.min,
    this.max,
    required this.unit,
    required this.currency,
  });

  factory PlacePricing.fromJson(Map<String, dynamic> json) => PlacePricing(
        min: (json['min'] as num?)?.toDouble(),
        max: (json['max'] as num?)?.toDouble(),
        unit: json['unit'] as String? ?? 'night',
        currency: json['currency'] as String? ?? 'KES',
      );

  Map<String, dynamic> toJson() => {
        if (min != null) 'min': min,
        if (max != null) 'max': max,
        'unit': unit,
        'currency': currency,
      };
}

class PlaceBookingSettings {
  final int? advanceNotice;
  final int? minDuration;
  final int? maxDuration;
  final String? cancellationPolicy;

  const PlaceBookingSettings({
    this.advanceNotice,
    this.minDuration,
    this.maxDuration,
    this.cancellationPolicy,
  });

  factory PlaceBookingSettings.fromJson(Map<String, dynamic> json) =>
      PlaceBookingSettings(
        advanceNotice: json['advanceNotice'] as int?,
        minDuration: json['minDuration'] as int?,
        maxDuration: json['maxDuration'] as int?,
        cancellationPolicy: json['cancellationPolicy'] as String?,
      );

  Map<String, dynamic> toJson() => {
        if (advanceNotice != null) 'advanceNotice': advanceNotice,
        if (minDuration != null) 'minDuration': minDuration,
        if (maxDuration != null) 'maxDuration': maxDuration,
        if (cancellationPolicy != null) 'cancellationPolicy': cancellationPolicy,
      };
}

class PlaceCategoryLink {
  final String categoryId;
  final String categoryName;
  final String categorySlug;
  final String? parentName;

  const PlaceCategoryLink({
    required this.categoryId,
    required this.categoryName,
    required this.categorySlug,
    this.parentName,
  });

  factory PlaceCategoryLink.fromJson(Map<String, dynamic> json) {
    final cat = json['category'] as Map<String, dynamic>? ?? {};
    final parent = cat['parent'] as Map<String, dynamic>?;
    return PlaceCategoryLink(
      categoryId: cat['id'] as String? ?? '',
      categoryName: cat['name'] as String? ?? '',
      categorySlug: cat['slug'] as String? ?? '',
      parentName: parent?['name'] as String?,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PlaceValidationResult  — from GET /api/places/:id/submit
// ─────────────────────────────────────────────────────────────────────────────

class PlaceValidationResult {
  final bool isValid;
  final List<String> missing;

  const PlaceValidationResult({required this.isValid, required this.missing});

  factory PlaceValidationResult.fromJson(Map<String, dynamic> json) =>
      PlaceValidationResult(
        isValid: json['isValid'] as bool? ?? false,
        missing: (json['missing'] as List<dynamic>?)
                ?.map((m) => m.toString())
                .toList() ??
            [],
      );
}