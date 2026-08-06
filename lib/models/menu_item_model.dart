import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MenuSectionModel / MenuItemModel
//
// Maps to the backend Dining shape (see /api/places/:placeId/menu-sections,
// /api/places/:placeId/menu-sections/:sectionId/items). Used narrowly — only
// as the authoritative type inside the admin Dining editor dialog
// (admin_place_wizard_screen.dart). Everywhere else in the existing
// nested-item pipeline (place_details_screen.dart's _nestedItems,
// booking_screen.dart's serviceOptions) keeps taking
// List<Map<String, dynamic>>, per the same narrow-boundary pattern used for
// RoomModel.
// ─────────────────────────────────────────────────────────────────────────────

enum DiningCategory {
  appetizers,
  starters,
  soups,
  salads,
  mainCourses,
  entrees,
  sides,
  riceDishes,
  noodleDishes,
  grills,
  curries,
  stews,
  desserts,
  fruits,
  iceCream,
  cakes,
  beverages,
  hotDrinks,
  coldDrinks,
  alcoholic,
  kidsMenu,
  buffetItems,
  chefSpecials;

  String get wireValue => switch (this) {
        DiningCategory.appetizers => 'APPETIZERS',
        DiningCategory.starters => 'STARTERS',
        DiningCategory.soups => 'SOUPS',
        DiningCategory.salads => 'SALADS',
        DiningCategory.mainCourses => 'MAIN_COURSES',
        DiningCategory.entrees => 'ENTREES',
        DiningCategory.sides => 'SIDES',
        DiningCategory.riceDishes => 'RICE_DISHES',
        DiningCategory.noodleDishes => 'NOODLE_DISHES',
        DiningCategory.grills => 'GRILLS',
        DiningCategory.curries => 'CURRIES',
        DiningCategory.stews => 'STEWS',
        DiningCategory.desserts => 'DESSERTS',
        DiningCategory.fruits => 'FRUITS',
        DiningCategory.iceCream => 'ICE_CREAM',
        DiningCategory.cakes => 'CAKES',
        DiningCategory.beverages => 'BEVERAGES',
        DiningCategory.hotDrinks => 'HOT_DRINKS',
        DiningCategory.coldDrinks => 'COLD_DRINKS',
        DiningCategory.alcoholic => 'ALCOHOLIC',
        DiningCategory.kidsMenu => 'KIDS_MENU',
        DiningCategory.buffetItems => 'BUFFET_ITEMS',
        DiningCategory.chefSpecials => 'CHEF_SPECIALS',
      };

  String get label => switch (this) {
        DiningCategory.appetizers => 'Appetizers',
        DiningCategory.starters => 'Starters',
        DiningCategory.soups => 'Soups',
        DiningCategory.salads => 'Salads',
        DiningCategory.mainCourses => 'Main Courses',
        DiningCategory.entrees => 'Entrees',
        DiningCategory.sides => 'Sides',
        DiningCategory.riceDishes => 'Rice Dishes',
        DiningCategory.noodleDishes => 'Noodle Dishes',
        DiningCategory.grills => 'Grills',
        DiningCategory.curries => 'Curries',
        DiningCategory.stews => 'Stews',
        DiningCategory.desserts => 'Desserts',
        DiningCategory.fruits => 'Fruits',
        DiningCategory.iceCream => 'Ice Cream',
        DiningCategory.cakes => 'Cakes',
        DiningCategory.beverages => 'Beverages',
        DiningCategory.hotDrinks => 'Hot Drinks',
        DiningCategory.coldDrinks => 'Cold Drinks',
        DiningCategory.alcoholic => 'Alcoholic',
        DiningCategory.kidsMenu => 'Kids Menu',
        DiningCategory.buffetItems => 'Buffet Items',
        DiningCategory.chefSpecials => 'Chef Specials',
      };

  static DiningCategory fromWire(String? value) =>
      DiningCategory.values.firstWhere((c) => c.wireValue == value,
          orElse: () => DiningCategory.mainCourses);
}

enum MealType {
  breakfast,
  brunch,
  lunch,
  dinner,
  snack,
  dessert,
  beverage,
  allDay,
  lateNight;

  String get wireValue => switch (this) {
        MealType.breakfast => 'BREAKFAST',
        MealType.brunch => 'BRUNCH',
        MealType.lunch => 'LUNCH',
        MealType.dinner => 'DINNER',
        MealType.snack => 'SNACK',
        MealType.dessert => 'DESSERT',
        MealType.beverage => 'BEVERAGE',
        MealType.allDay => 'ALL_DAY',
        MealType.lateNight => 'LATE_NIGHT',
      };

  String get label => switch (this) {
        MealType.breakfast => 'Breakfast',
        MealType.brunch => 'Brunch',
        MealType.lunch => 'Lunch',
        MealType.dinner => 'Dinner',
        MealType.snack => 'Snack',
        MealType.dessert => 'Dessert',
        MealType.beverage => 'Beverage',
        MealType.allDay => 'All Day',
        MealType.lateNight => 'Late Night',
      };

  static MealType fromWire(String? value) => MealType.values
      .firstWhere((m) => m.wireValue == value, orElse: () => MealType.allDay);
}

enum CuisineType {
  african,
  swahili,
  northAfrican,
  westAfrican,
  southAfrican,
  italian,
  french,
  spanish,
  greek,
  british,
  chinese,
  japanese,
  korean,
  thai,
  vietnamese,
  indian,
  mexican,
  brazilian,
  american,
  peruvian,
  lebanese,
  turkish,
  israeli,
  mediterranean,
  fusion,
  international,
  fastFood;

  String get wireValue => switch (this) {
        CuisineType.african => 'AFRICAN',
        CuisineType.swahili => 'SWAHILI',
        CuisineType.northAfrican => 'NORTH_AFRICAN',
        CuisineType.westAfrican => 'WEST_AFRICAN',
        CuisineType.southAfrican => 'SOUTH_AFRICAN',
        CuisineType.italian => 'ITALIAN',
        CuisineType.french => 'FRENCH',
        CuisineType.spanish => 'SPANISH',
        CuisineType.greek => 'GREEK',
        CuisineType.british => 'BRITISH',
        CuisineType.chinese => 'CHINESE',
        CuisineType.japanese => 'JAPANESE',
        CuisineType.korean => 'KOREAN',
        CuisineType.thai => 'THAI',
        CuisineType.vietnamese => 'VIETNAMESE',
        CuisineType.indian => 'INDIAN',
        CuisineType.mexican => 'MEXICAN',
        CuisineType.brazilian => 'BRAZILIAN',
        CuisineType.american => 'AMERICAN',
        CuisineType.peruvian => 'PERUVIAN',
        CuisineType.lebanese => 'LEBANESE',
        CuisineType.turkish => 'TURKISH',
        CuisineType.israeli => 'ISRAELI',
        CuisineType.mediterranean => 'MEDITERRANEAN',
        CuisineType.fusion => 'FUSION',
        CuisineType.international => 'INTERNATIONAL',
        CuisineType.fastFood => 'FAST_FOOD',
      };

  String get label => switch (this) {
        CuisineType.african => 'African',
        CuisineType.swahili => 'Swahili',
        CuisineType.northAfrican => 'North African',
        CuisineType.westAfrican => 'West African',
        CuisineType.southAfrican => 'South African',
        CuisineType.italian => 'Italian',
        CuisineType.french => 'French',
        CuisineType.spanish => 'Spanish',
        CuisineType.greek => 'Greek',
        CuisineType.british => 'British',
        CuisineType.chinese => 'Chinese',
        CuisineType.japanese => 'Japanese',
        CuisineType.korean => 'Korean',
        CuisineType.thai => 'Thai',
        CuisineType.vietnamese => 'Vietnamese',
        CuisineType.indian => 'Indian',
        CuisineType.mexican => 'Mexican',
        CuisineType.brazilian => 'Brazilian',
        CuisineType.american => 'American',
        CuisineType.peruvian => 'Peruvian',
        CuisineType.lebanese => 'Lebanese',
        CuisineType.turkish => 'Turkish',
        CuisineType.israeli => 'Israeli',
        CuisineType.mediterranean => 'Mediterranean',
        CuisineType.fusion => 'Fusion',
        CuisineType.international => 'International',
        CuisineType.fastFood => 'Fast Food',
      };

  static CuisineType? fromWire(String? value) {
    if (value == null) return null;
    for (final c in CuisineType.values) {
      if (c.wireValue == value) return c;
    }
    return null;
  }
}

enum DietaryOption {
  vegetarian,
  vegan,
  glutenFree,
  dairyFree,
  nutFree,
  halal,
  kosher,
  lowCarb,
  keto,
  paleo;

  String get wireValue => switch (this) {
        DietaryOption.vegetarian => 'VEGETARIAN',
        DietaryOption.vegan => 'VEGAN',
        DietaryOption.glutenFree => 'GLUTEN_FREE',
        DietaryOption.dairyFree => 'DAIRY_FREE',
        DietaryOption.nutFree => 'NUT_FREE',
        DietaryOption.halal => 'HALAL',
        DietaryOption.kosher => 'KOSHER',
        DietaryOption.lowCarb => 'LOW_CARB',
        DietaryOption.keto => 'KETO',
        DietaryOption.paleo => 'PALEO',
      };

  String get label => switch (this) {
        DietaryOption.vegetarian => 'Vegetarian',
        DietaryOption.vegan => 'Vegan',
        DietaryOption.glutenFree => 'Gluten-Free',
        DietaryOption.dairyFree => 'Dairy-Free',
        DietaryOption.nutFree => 'Nut-Free',
        DietaryOption.halal => 'Halal',
        DietaryOption.kosher => 'Kosher',
        DietaryOption.lowCarb => 'Low-Carb',
        DietaryOption.keto => 'Keto',
        DietaryOption.paleo => 'Paleo',
      };

  static DietaryOption? fromWire(String? value) {
    if (value == null) return null;
    for (final d in DietaryOption.values) {
      if (d.wireValue == value) return d;
    }
    return null;
  }
}

class MenuSectionModel {
  final String? id;
  final String? placeId;
  // The backend REST API's own id, once BackendMenuSync has confirmed a
  // create there — see the matching field on RoomModel for the full
  // rationale.
  final String? restId;
  final String name;
  final String? description;
  final int sortOrder;
  final bool isActive;

  const MenuSectionModel({
    this.id,
    this.placeId,
    this.restId,
    required this.name,
    this.description,
    this.sortOrder = 0,
    this.isActive = true,
  });

  factory MenuSectionModel.fromJson(Map<String, dynamic> json) =>
      MenuSectionModel(
        id: json['id'] as String?,
        placeId: json['placeId'] as String?,
        restId: json['restId'] as String?,
        name: json['name'] as String? ?? '',
        description: json['description'] as String?,
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
        isActive: json['isActive'] as bool? ?? true,
      );

  Map<String, dynamic> toCreateMap() => {
        'name': name,
        if (description != null) 'description': description,
        'sortOrder': sortOrder,
        'isActive': isActive,
      };

  /// Reads a MenuSections/{sectionId} Firestore doc — the doc id is always
  /// the canonical `id` (Firestore is the authoritative store as of Phase 3;
  /// see MenuService).
  factory MenuSectionModel.fromFirestore(
          DocumentSnapshot<Map<String, dynamic>> doc) =>
      MenuSectionModel.fromJson({...?doc.data(), 'id': doc.id});

  /// Body for MenuSections/{sectionId} — same fields as toCreateMap() plus
  /// placeId.
  Map<String, dynamic> toFirestoreMap({required String placeId}) => {
        ...toCreateMap(),
        'placeId': placeId,
      };
}

class MenuItemModel {
  final String? id;
  final String? placeId;
  final String? sectionId;
  // The backend REST API's own id, once BackendMenuSync has confirmed a
  // create there — see the matching field on RoomModel for the full
  // rationale.
  final String? restId;
  final String name;
  final String? description;
  final DiningCategory? category;
  final MealType mealType;
  final CuisineType? cuisineType;
  final List<String> ingredients;
  final List<String> allergens;
  final List<DietaryOption> dietaryOptions;
  final int spicyLevel;
  final bool isVegetarian;
  final bool isVegan;
  final bool isGlutenFree;
  final int? prepTime;
  final int? calories;
  final String? servingSize;
  final double price;
  final String currency;
  final bool isAvailable;
  final bool isSignatureDish;
  final bool isChefSpecial;
  final bool isSeasonalDish;
  final List<String> images;
  final List<String> pairsWith;
  final int sortOrder;

  const MenuItemModel({
    this.id,
    this.placeId,
    this.sectionId,
    this.restId,
    required this.name,
    this.description,
    this.category,
    this.mealType = MealType.allDay,
    this.cuisineType,
    this.ingredients = const [],
    this.allergens = const [],
    this.dietaryOptions = const [],
    this.spicyLevel = 0,
    this.isVegetarian = false,
    this.isVegan = false,
    this.isGlutenFree = false,
    this.prepTime,
    this.calories,
    this.servingSize,
    required this.price,
    this.currency = 'KES',
    this.isAvailable = true,
    this.isSignatureDish = false,
    this.isChefSpecial = false,
    this.isSeasonalDish = false,
    this.images = const [],
    this.pairsWith = const [],
    this.sortOrder = 0,
  });

  /// Compact "Vegetarian · Gluten-Free" style summary — the Dining
  /// equivalent of RoomModel.bedsSummaryFromMap, used by read-only display
  /// screens without instantiating a full MenuItemModel.
  static String dietarySummaryFromMap(Map<String, dynamic> map) {
    final raw = (map['dietaryOptions'] as List<dynamic>?) ?? const [];
    final labels = raw
        .map((d) => DietaryOption.fromWire(d?.toString())?.label)
        .whereType<String>()
        .toList(growable: false);
    return labels.join(' · ');
  }

  factory MenuItemModel.fromJson(Map<String, dynamic> json) => MenuItemModel(
        id: json['id'] as String?,
        placeId: json['placeId'] as String?,
        sectionId: json['sectionId'] as String?,
        restId: json['restId'] as String?,
        name: json['name'] as String? ?? '',
        description: json['description'] as String?,
        category: json['category'] != null
            ? DiningCategory.fromWire(json['category'] as String?)
            : null,
        mealType: MealType.fromWire(json['mealType'] as String?),
        cuisineType: CuisineType.fromWire(json['cuisineType'] as String?),
        ingredients: (json['ingredients'] as List<dynamic>?)
                ?.map((i) => i.toString())
                .toList() ??
            [],
        allergens: (json['allergens'] as List<dynamic>?)
                ?.map((a) => a.toString())
                .toList() ??
            [],
        dietaryOptions: (json['dietaryOptions'] as List<dynamic>?)
                ?.map((d) => DietaryOption.fromWire(d?.toString()))
                .whereType<DietaryOption>()
                .toList() ??
            [],
        spicyLevel: (json['spicyLevel'] as num?)?.toInt() ?? 0,
        isVegetarian: json['isVegetarian'] as bool? ?? false,
        isVegan: json['isVegan'] as bool? ?? false,
        isGlutenFree: json['isGlutenFree'] as bool? ?? false,
        prepTime: (json['prepTime'] as num?)?.toInt(),
        calories: (json['calories'] as num?)?.toInt(),
        servingSize: json['servingSize'] as String?,
        price: (json['price'] as num?)?.toDouble() ?? 0,
        currency: json['currency'] as String? ?? 'KES',
        isAvailable: json['isAvailable'] as bool? ?? true,
        isSignatureDish: json['isSignatureDish'] as bool? ?? false,
        isChefSpecial: json['isChefSpecial'] as bool? ?? false,
        isSeasonalDish: json['isSeasonalDish'] as bool? ?? false,
        images: (json['images'] as List<dynamic>?)
                ?.map((i) => i.toString())
                .toList() ??
            [],
        pairsWith: (json['pairsWith'] as List<dynamic>?)
                ?.map((p) => p.toString())
                .toList() ??
            [],
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      );

  /// Alias — the wizard's existing nested-item lists already call these
  /// "maps" throughout, not "json".
  factory MenuItemModel.fromMap(Map<String, dynamic> map) =>
      MenuItemModel.fromJson(map);

  /// Body for POST .../menu-sections/:sectionId/items (sent as one element
  /// of {'items': [...]}) and PATCH .../items/:itemId (this backend's PATCH
  /// already accepts partial-or-full bodies). Omits null-optional fields so
  /// backend defaults apply rather than overwriting with null.
  Map<String, dynamic> toCreateMap() => {
        'name': name,
        if (description != null) 'description': description,
        if (category != null) 'category': category!.wireValue,
        'mealType': mealType.wireValue,
        if (cuisineType != null) 'cuisineType': cuisineType!.wireValue,
        'ingredients': ingredients,
        'allergens': allergens,
        'dietaryOptions': dietaryOptions.map((d) => d.wireValue).toList(),
        'spicyLevel': spicyLevel,
        'isVegetarian': isVegetarian,
        'isVegan': isVegan,
        'isGlutenFree': isGlutenFree,
        if (prepTime != null) 'prepTime': prepTime,
        if (calories != null) 'calories': calories,
        if (servingSize != null) 'servingSize': servingSize,
        'price': price,
        'currency': currency,
        'isAvailable': isAvailable,
        'isSignatureDish': isSignatureDish,
        'isChefSpecial': isChefSpecial,
        'isSeasonalDish': isSeasonalDish,
        'images': images,
        'pairsWith': pairsWith,
        'sortOrder': sortOrder,
      };

  Map<String, dynamic> toUpdateMap() => toCreateMap();

  /// Reads a MenuItems/{itemId} Firestore doc — the doc id is always the
  /// canonical `id` (Firestore is the authoritative store as of Phase 3; see
  /// MenuService). `sectionId`/`placeId` are already plain fields on the
  /// stored map, so fromJson picks them up unchanged.
  factory MenuItemModel.fromFirestore(
          DocumentSnapshot<Map<String, dynamic>> doc) =>
      MenuItemModel.fromJson({...?doc.data(), 'id': doc.id});

  /// Body for MenuItems/{itemId} — same fields as toCreateMap() plus
  /// placeId/sectionId.
  Map<String, dynamic> toFirestoreMap(
          {required String placeId, required String sectionId}) =>
      {
        ...toCreateMap(),
        'placeId': placeId,
        'sectionId': sectionId,
      };
}
