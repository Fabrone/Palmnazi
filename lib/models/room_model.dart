import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RoomModel
//
// Maps to the backend Room shape (see /api/places/:placeId/rooms,
// /api/rooms/:id). Used narrowly — only as the authoritative type inside the
// admin room editor dialog (admin_place_wizard_screen.dart). Everywhere else
// in the existing nested-item pipeline (place_details_screen.dart's
// _nestedItems, booking_screen.dart's serviceOptions) keeps taking
// List<Map<String, dynamic>>, exactly as it already does for menu items,
// shows, exhibitions and artifacts — see room_model.dart's sibling models
// (to be added for those categories) for the same narrow-boundary pattern.
// ─────────────────────────────────────────────────────────────────────────────

enum RoomType {
  single,
  double_,
  twin,
  suite,
  family,
  penthouse,
  dormitory;

  String get wireValue => switch (this) {
        RoomType.single => 'SINGLE',
        RoomType.double_ => 'DOUBLE',
        RoomType.twin => 'TWIN',
        RoomType.suite => 'SUITE',
        RoomType.family => 'FAMILY',
        RoomType.penthouse => 'PENTHOUSE',
        RoomType.dormitory => 'DORMITORY',
      };

  String get label => switch (this) {
        RoomType.single => 'Single',
        RoomType.double_ => 'Double',
        RoomType.twin => 'Twin',
        RoomType.suite => 'Suite',
        RoomType.family => 'Family',
        RoomType.penthouse => 'Penthouse',
        RoomType.dormitory => 'Dormitory',
      };

  static RoomType fromWire(String? value) => RoomType.values.firstWhere(
        (t) => t.wireValue == value,
        orElse: () => RoomType.double_,
      );
}

enum BedType {
  single,
  double_,
  queen,
  king,
  bunk,
  sofaBed;

  String get wireValue => switch (this) {
        BedType.single => 'SINGLE',
        BedType.double_ => 'DOUBLE',
        BedType.queen => 'QUEEN',
        BedType.king => 'KING',
        BedType.bunk => 'BUNK',
        BedType.sofaBed => 'SOFA_BED',
      };

  String get label => switch (this) {
        BedType.single => 'Single',
        BedType.double_ => 'Double',
        BedType.queen => 'Queen',
        BedType.king => 'King',
        BedType.bunk => 'Bunk',
        BedType.sofaBed => 'Sofa Bed',
      };

  static BedType fromWire(String? value) => BedType.values.firstWhere(
        (t) => t.wireValue == value,
        orElse: () => BedType.single,
      );
}

class BedModel {
  final BedType bedType;
  final int quantity;

  const BedModel({required this.bedType, this.quantity = 1});

  factory BedModel.fromJson(Map<String, dynamic> json) => BedModel(
        bedType: BedType.fromWire(json['bedType'] as String?),
        quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      );

  Map<String, dynamic> toJson() => {
        'bedType': bedType.wireValue,
        'quantity': quantity,
      };
}

class RoomSeasonalPrice {
  final String season;
  final String? startDate;
  final String? endDate;
  final double price;

  const RoomSeasonalPrice({
    required this.season,
    this.startDate,
    this.endDate,
    required this.price,
  });

  factory RoomSeasonalPrice.fromJson(Map<String, dynamic> json) =>
      RoomSeasonalPrice(
        season: json['season'] as String? ?? '',
        startDate: json['startDate'] as String?,
        endDate: json['endDate'] as String?,
        price: (json['price'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'season': season,
        if (startDate != null) 'startDate': startDate,
        if (endDate != null) 'endDate': endDate,
        'price': price,
      };
}

class RoomMetadata {
  final String? viewType;
  final int? bathrooms;
  final String? bathroomType;

  const RoomMetadata({this.viewType, this.bathrooms, this.bathroomType});

  factory RoomMetadata.fromJson(Map<String, dynamic> json) => RoomMetadata(
        viewType: json['viewType'] as String?,
        bathrooms: (json['bathrooms'] as num?)?.toInt(),
        bathroomType: json['bathroomType'] as String?,
      );

  Map<String, dynamic> toJson() => {
        if (viewType != null) 'viewType': viewType,
        if (bathrooms != null) 'bathrooms': bathrooms,
        if (bathroomType != null) 'bathroomType': bathroomType,
      };

  bool get isEmpty =>
      viewType == null && bathrooms == null && bathroomType == null;
}

class RoomModel {
  final String? id;
  final String? placeId;
  // The backend REST API's own id for this room, once BackendRoomSync has
  // confirmed a create there — null until then (or forever, if the backend
  // stays unreachable). Never sent to the backend itself; purely local
  // bookkeeping so a later edit/delete sync knows what to target. See
  // backend_room_sync.dart.
  final String? restId;
  final String name;
  final String? description;
  final RoomType roomType;
  final String? roomNumber;
  final int? floor;
  final int maxGuests;
  final int maxAdults;
  final int maxChildren;
  final double? sizeSquareMeters;
  final bool hasBalcony;
  final bool hasKitchen;
  final bool hasLivingRoom;
  final List<String> amenities;
  final double basePrice;
  final double? weekendPrice;
  final String currency;
  final List<RoomSeasonalPrice> seasonalPricing;
  final bool isAvailable;
  final List<String> images;
  final RoomMetadata? metadata;
  final int sortOrder;
  final List<BedModel> beds;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const RoomModel({
    this.id,
    this.placeId,
    this.restId,
    required this.name,
    this.description,
    this.roomType = RoomType.double_,
    this.roomNumber,
    this.floor,
    this.maxGuests = 2,
    this.maxAdults = 2,
    this.maxChildren = 0,
    this.sizeSquareMeters,
    this.hasBalcony = false,
    this.hasKitchen = false,
    this.hasLivingRoom = false,
    this.amenities = const [],
    required this.basePrice,
    this.weekendPrice,
    this.currency = 'KES',
    this.seasonalPricing = const [],
    this.isAvailable = true,
    this.images = const [],
    this.metadata,
    this.sortOrder = 0,
    this.beds = const [],
    this.createdAt,
    this.updatedAt,
  });

  String get roomTypeLabel => roomType.label;

  String get bedsSummary => RoomModel.formatBeds(beds
      .map((b) => MapEntry(b.bedType.label, b.quantity))
      .toList(growable: false));

  /// Read-only formatting helper — lets place_details_screen.dart and
  /// booking_screen.dart render an identical bed summary from a raw
  /// `Map<String, dynamic>` without instantiating a full RoomModel (those
  /// screens are read-only consumers of the polymorphic nested-item Maps,
  /// per the narrow-boundary scope decision for this feature).
  static String bedsSummaryFromMap(Map<String, dynamic> map) {
    final beds = (map['beds'] as List<dynamic>?) ?? const [];
    final entries = beds
        .whereType<Map<String, dynamic>>()
        .map((b) => MapEntry(
              BedType.fromWire(b['bedType'] as String?).label,
              (b['quantity'] as num?)?.toInt() ?? 1,
            ))
        .toList(growable: false);
    return formatBeds(entries);
  }

  static String formatBeds(List<MapEntry<String, int>> entries) {
    if (entries.isEmpty) return '';
    return entries.map((e) => '${e.value} ${e.key}').join(', ');
  }

  factory RoomModel.fromJson(Map<String, dynamic> json) => RoomModel(
        id: json['id'] as String?,
        placeId: json['placeId'] as String?,
        name: json['name'] as String? ?? '',
        description: json['description'] as String?,
        roomType: RoomType.fromWire(json['roomType'] as String?),
        roomNumber: json['roomNumber'] as String?,
        floor: (json['floor'] as num?)?.toInt(),
        maxGuests: (json['maxGuests'] as num?)?.toInt() ?? 2,
        maxAdults: (json['maxAdults'] as num?)?.toInt() ?? 2,
        maxChildren: (json['maxChildren'] as num?)?.toInt() ?? 0,
        sizeSquareMeters: (json['sizeSquareMeters'] as num?)?.toDouble(),
        hasBalcony: json['hasBalcony'] as bool? ?? false,
        hasKitchen: json['hasKitchen'] as bool? ?? false,
        hasLivingRoom: json['hasLivingRoom'] as bool? ?? false,
        amenities: (json['amenities'] as List<dynamic>?)
                ?.map((a) => a.toString())
                .toList() ??
            [],
        basePrice: (json['basePrice'] as num?)?.toDouble() ?? 0,
        weekendPrice: (json['weekendPrice'] as num?)?.toDouble(),
        currency: json['currency'] as String? ?? 'KES',
        seasonalPricing: (json['seasonalPricing'] as List<dynamic>?)
                ?.map((s) =>
                    RoomSeasonalPrice.fromJson(s as Map<String, dynamic>))
                .toList() ??
            [],
        isAvailable: json['isAvailable'] as bool? ?? true,
        images: (json['images'] as List<dynamic>?)
                ?.map((i) => i.toString())
                .toList() ??
            [],
        metadata: json['metadata'] != null
            ? RoomMetadata.fromJson(json['metadata'] as Map<String, dynamic>)
            : null,
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
        beds: (json['beds'] as List<dynamic>?)
                ?.map((b) => BedModel.fromJson(b as Map<String, dynamic>))
                .toList() ??
            [],
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String)
            : null,
        updatedAt: json['updatedAt'] != null
            ? DateTime.tryParse(json['updatedAt'] as String)
            : null,
      );

  /// Alias — the wizard's existing nested-item lists already call these
  /// "maps" throughout, not "json".
  factory RoomModel.fromMap(Map<String, dynamic> map) =>
      RoomModel.fromJson(map);

  /// Reads a Rooms/{roomId} Firestore doc — the doc id is always the
  /// canonical `id` (Firestore is the authoritative store as of Phase 3; see
  /// RoomService). createdAt/updatedAt arrive as Firestore Timestamps, not
  /// ISO strings, so they're stripped before delegating to fromJson (which
  /// assumes strings) and reattached via copyWith afterward.
  factory RoomModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final raw = doc.data() ?? {};
    final sanitized = Map<String, dynamic>.from(raw)
      ..remove('createdAt')
      ..remove('updatedAt');
    return RoomModel.fromJson(sanitized).copyWith(
      id: doc.id,
      restId: raw['restId'] as String?,
      createdAt: (raw['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (raw['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Body for Rooms/{roomId} — same fields as toCreateMap() plus placeId.
  /// createdAt/updatedAt are set by RoomService (FieldValue.serverTimestamp())
  /// rather than here, since create vs. update need different treatment
  /// (createdAt must only ever be set once).
  Map<String, dynamic> toFirestoreMap({required String placeId}) => {
        ...toCreateMap(),
        'placeId': placeId,
      };

  /// Body for POST .../rooms (sent as one element of {'rooms': [...]}) and
  /// PATCH /api/rooms/:id (this backend's PATCH already accepts
  /// partial-or-full bodies). Omits null-optional fields so backend
  /// defaults apply rather than overwriting with null; beds is always
  /// included — even as [] — since the documented create-room example
  /// always shows a beds array, so an explicit empty list is more honest
  /// than omitting the key entirely.
  Map<String, dynamic> toCreateMap() => {
        'name': name,
        if (description != null) 'description': description,
        'roomType': roomType.wireValue,
        if (roomNumber != null) 'roomNumber': roomNumber,
        if (floor != null) 'floor': floor,
        'maxGuests': maxGuests,
        'maxAdults': maxAdults,
        'maxChildren': maxChildren,
        if (sizeSquareMeters != null) 'sizeSquareMeters': sizeSquareMeters,
        'hasBalcony': hasBalcony,
        'hasKitchen': hasKitchen,
        'hasLivingRoom': hasLivingRoom,
        'amenities': amenities,
        'basePrice': basePrice,
        if (weekendPrice != null) 'weekendPrice': weekendPrice,
        'currency': currency,
        if (seasonalPricing.isNotEmpty)
          'seasonalPricing': seasonalPricing.map((s) => s.toJson()).toList(),
        'isAvailable': isAvailable,
        'images': images,
        if (metadata != null && !metadata!.isEmpty)
          'metadata': metadata!.toJson(),
        'sortOrder': sortOrder,
        'beds': beds.map((b) => b.toJson()).toList(),
      };

  Map<String, dynamic> toUpdateMap() => toCreateMap();

  RoomModel copyWith({
    String? id,
    String? placeId,
    String? restId,
    String? name,
    String? description,
    RoomType? roomType,
    String? roomNumber,
    int? floor,
    int? maxGuests,
    int? maxAdults,
    int? maxChildren,
    double? sizeSquareMeters,
    bool? hasBalcony,
    bool? hasKitchen,
    bool? hasLivingRoom,
    List<String>? amenities,
    double? basePrice,
    double? weekendPrice,
    String? currency,
    List<RoomSeasonalPrice>? seasonalPricing,
    bool? isAvailable,
    List<String>? images,
    RoomMetadata? metadata,
    int? sortOrder,
    List<BedModel>? beds,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      RoomModel(
        id: id ?? this.id,
        placeId: placeId ?? this.placeId,
        restId: restId ?? this.restId,
        name: name ?? this.name,
        description: description ?? this.description,
        roomType: roomType ?? this.roomType,
        roomNumber: roomNumber ?? this.roomNumber,
        floor: floor ?? this.floor,
        maxGuests: maxGuests ?? this.maxGuests,
        maxAdults: maxAdults ?? this.maxAdults,
        maxChildren: maxChildren ?? this.maxChildren,
        sizeSquareMeters: sizeSquareMeters ?? this.sizeSquareMeters,
        hasBalcony: hasBalcony ?? this.hasBalcony,
        hasKitchen: hasKitchen ?? this.hasKitchen,
        hasLivingRoom: hasLivingRoom ?? this.hasLivingRoom,
        amenities: amenities ?? this.amenities,
        basePrice: basePrice ?? this.basePrice,
        weekendPrice: weekendPrice ?? this.weekendPrice,
        currency: currency ?? this.currency,
        seasonalPricing: seasonalPricing ?? this.seasonalPricing,
        isAvailable: isAvailable ?? this.isAvailable,
        images: images ?? this.images,
        metadata: metadata ?? this.metadata,
        sortOrder: sortOrder ?? this.sortOrder,
        beds: beds ?? this.beds,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
