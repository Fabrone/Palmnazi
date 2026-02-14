import 'package:flutter/material.dart';

/// Resort City Model
/// Represents a resort city destination
class ResortCityItem {
  final String id;
  final String name;
  final String tagline;
  final String description;
  final String imagePath;
  final Color color;
  final List<String> highlights;

  ResortCityItem({
    required this.id,
    required this.name,
    required this.tagline,
    required this.description,
    required this.imagePath,
    required this.color,
    required this.highlights,
  });

  /// Get the correct asset path for the image
  String get assetPath {
    // Ensure the path starts with 'assets/'
    if (imagePath.startsWith('assets/')) {
      return imagePath;
    } else if (imagePath.startsWith('images/')) {
      return 'assets/$imagePath';
    } else {
      return 'assets/images/$imagePath';
    }
  }

  /// Factory constructor for creating from JSON
  factory ResortCityItem.fromJson(Map<String, dynamic> json) {
    return ResortCityItem(
      id: json['id'] as String,
      name: json['name'] as String,
      tagline: json['tagline'] as String,
      description: json['description'] as String,
      imagePath: json['imagePath'] as String? ?? json['imageUrl'] as String,
      color: Color(int.parse(json['colorHex'].replaceFirst('#', '0xFF'))),
      highlights: List<String>.from(json['highlights'] as List),
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'tagline': tagline,
      'description': description,
      'imagePath': imagePath,
      'colorHex': '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
      'highlights': highlights,
    };
  }
}

/// Channel Model
/// Represents a category/channel within a resort city
class ChannelItem {
  final String id;
  final IconData icon;
  final String title;
  final String description;
  final Color color;
  final String imagePath;
  final List<String> subcategories;

  ChannelItem({
    required this.id,
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    required this.imagePath,
    required this.subcategories,
  });

  /// Get the correct asset path for the image
  String get assetPath {
    // Ensure the path starts with 'assets/'
    if (imagePath.startsWith('assets/')) {
      return imagePath;
    } else if (imagePath.startsWith('images/')) {
      return 'assets/$imagePath';
    } else {
      return 'assets/images/$imagePath';
    }
  }

  /// Factory constructor for creating from JSON
  factory ChannelItem.fromJson(Map<String, dynamic> json) {
    return ChannelItem(
      id: json['id'] as String,
      icon: _getIconFromName(json['iconName'] as String),
      title: json['title'] as String,
      description: json['description'] as String,
      color: Color(int.parse(json['colorHex'].replaceFirst('#', '0xFF'))),
      imagePath: json['imagePath'] as String? ?? json['imageUrl'] as String,
      subcategories: List<String>.from(json['subcategories'] as List),
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'iconName': _getIconName(icon),
      'title': title,
      'description': description,
      'colorHex': '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
      'imagePath': imagePath,
      'subcategories': subcategories,
    };
  }

  /// Helper method to get IconData from string name
  static IconData _getIconFromName(String name) {
    switch (name) {
      case 'king_bed_outlined':
        return Icons.king_bed_outlined;
      case 'restaurant_menu':
        return Icons.restaurant_menu;
      case 'celebration':
        return Icons.celebration;
      case 'shopping_bag_outlined':
        return Icons.shopping_bag_outlined;
      case 'terrain':
        return Icons.terrain;
      case 'spa_outlined':
        return Icons.spa_outlined;
      default:
        return Icons.business;
    }
  }

  /// Helper method to get icon name from IconData
  static String _getIconName(IconData icon) {
    if (icon == Icons.king_bed_outlined) return 'king_bed_outlined';
    if (icon == Icons.restaurant_menu) return 'restaurant_menu';
    if (icon == Icons.celebration) return 'celebration';
    if (icon == Icons.shopping_bag_outlined) return 'shopping_bag_outlined';
    if (icon == Icons.terrain) return 'terrain';
    if (icon == Icons.spa_outlined) return 'spa_outlined';
    return 'business';
  }
}

/// Place/Business Model
/// Represents a specific place or business within a channel
class PlaceItem {
  final String id;
  final String name;
  final String category;
  final double rating;
  final int reviewCount;
  final String description;
  final String imagePath;
  final String address;
  final String phone;
  final String website;
  final List<String> features;
  final String priceRange;
  final bool isOpen;

  PlaceItem({
    required this.id,
    required this.name,
    required this.category,
    required this.rating,
    required this.reviewCount,
    required this.description,
    required this.imagePath,
    required this.address,
    required this.phone,
    required this.website,
    required this.features,
    required this.priceRange,
    required this.isOpen,
  });

  /// Get the correct asset path for the image
  String get assetPath {
    // Ensure the path starts with 'assets/'
    if (imagePath.startsWith('assets/')) {
      return imagePath;
    } else if (imagePath.startsWith('images/')) {
      return 'assets/$imagePath';
    } else {
      return 'assets/images/$imagePath';
    }
  }

  /// Factory constructor for creating from JSON
  factory PlaceItem.fromJson(Map<String, dynamic> json) {
    return PlaceItem(
      id: json['id'] as String,
      name: json['name'] as String,
      category: json['category'] as String,
      rating: (json['rating'] as num).toDouble(),
      reviewCount: json['reviewCount'] as int,
      description: json['description'] as String,
      imagePath: json['imagePath'] as String? ?? json['imageUrl'] as String,
      address: json['address'] as String,
      phone: json['phone'] as String,
      website: json['website'] as String,
      features: List<String>.from(json['features'] as List),
      priceRange: json['priceRange'] as String,
      isOpen: json['isOpen'] as bool,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'rating': rating,
      'reviewCount': reviewCount,
      'description': description,
      'imagePath': imagePath,
      'address': address,
      'phone': phone,
      'website': website,
      'features': features,
      'priceRange': priceRange,
      'isOpen': isOpen,
    };
  }
}