// ─────────────────────────────────────────────────────────────────────────────
// CategoryModel
//
// Maps to the backend /api/categories response shape.
// A category is either a root (parentId == null) or a subcategory.
// The `children` list is only populated when the API is called with
// ?includeChildren=true or ?tree=true.
// ─────────────────────────────────────────────────────────────────────────────

class CategoryModel {
  final String id;
  final String name;
  final String slug;
  final String? parentId;
  final String? icon;
  final String? description;
  final int sortOrder;
  final bool isActive;
  final CategoryModel? parent;
  final List<CategoryModel> children;
  final int childrenCount;
  final int placeLinksCount;

  const CategoryModel({
    required this.id,
    required this.name,
    required this.slug,
    this.parentId,
    this.icon,
    this.description,
    required this.sortOrder,
    required this.isActive,
    this.parent,
    this.children = const [],
    this.childrenCount = 0,
    this.placeLinksCount = 0,
  });

  bool get isRoot => parentId == null;

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String,
      parentId: json['parentId'] as String?,
      icon: json['icon'] as String?,
      description: json['description'] as String?,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      isActive: json['isActive'] as bool? ?? true,
      parent: json['parent'] != null
          ? CategoryModel.fromJson(json['parent'] as Map<String, dynamic>)
          : null,
      children: (json['children'] as List<dynamic>?)
              ?.map((c) => CategoryModel.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
      childrenCount: ((json['_count'] as Map<String, dynamic>?)?['children'] as num?)?.toInt() ?? 0,
      placeLinksCount: ((json['_count'] as Map<String, dynamic>?)?['placeLinks'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'slug': slug,
        'parentId': parentId,
        'icon': icon,
        'description': description,
        'sortOrder': sortOrder,
        'isActive': isActive,
      };

  CategoryModel copyWith({
    String? name,
    String? slug,
    String? icon,
    String? description,
    int? sortOrder,
    bool? isActive,
    String? parentId,
  }) {
    return CategoryModel(
      id: id,
      name: name ?? this.name,
      slug: slug ?? this.slug,
      parentId: parentId ?? this.parentId,
      icon: icon ?? this.icon,
      description: description ?? this.description,
      sortOrder: sortOrder ?? this.sortOrder,
      isActive: isActive ?? this.isActive,
      parent: parent,
      children: children,
      childrenCount: childrenCount,
      placeLinksCount: placeLinksCount,
    );
  }

  @override
  String toString() => 'CategoryModel(id: $id, name: $name, slug: $slug, parentId: $parentId)';

  @override
  bool operator ==(Object other) => other is CategoryModel && other.id == id;

  @override
  int get hashCode => id.hashCode;
}