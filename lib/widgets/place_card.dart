import 'package:flutter/material.dart';
import 'package:palmnazi/models/place_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PlaceCard
//
// Shared listing card used by category_screen.dart (places within one
// service/category) and resort_city_screen.dart's "All Listings" tab (every
// place in a city, regardless of category) — extracted so both render
// identically without duplicating ~300 lines of card/image/badge logic.
// ─────────────────────────────────────────────────────────────────────────────

abstract final class PlaceCardColors {
  static const Color aqua = Color(0xFF00B8D4);
  static const Color aquaBright = Color(0xFF00E5FF);
  static const Color deepBlue = Color(0xFF071829);
}

// ─────────────────────────────────────────────────────────────────────────────
// PlaceModel display helpers
//
// These computed values are derived from the fields PlaceModel DOES have.
// Declared as extension methods rather than adding them to the model itself,
// keeping the model as the single source of truth for backend field mapping
// while giving the UI the convenience accessors it needs.
// ─────────────────────────────────────────────────────────────────────────────
extension PlaceDisplayHelpers on PlaceModel {
  /// ID of the first linked category, or null if no category links exist.
  String? get primaryCategoryId =>
      categoryLinks.isNotEmpty ? categoryLinks.first.categoryId : null;

  /// Name of the first linked category, or null if no category links exist.
  String? get primaryCategoryName =>
      categoryLinks.isNotEmpty ? categoryLinks.first.categoryName : null;

  /// Rating from the flexible attributes map, cast to double? if present.
  double? get rating {
    final v = attributes['rating'];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  /// Review count from the flexible attributes map, cast to int? if present.
  int? get reviewCount {
    final v = attributes['reviewCount'];
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  /// Whether the place is currently open, from attributes['isOpen'].
  /// Returns null (not shown) when the field is absent.
  bool? get isOpen {
    final v = attributes['isOpen'];
    if (v is bool) return v;
    if (v is String) {
      if (v == 'true') return true;
      if (v == 'false') return false;
    }
    return null;
  }

  /// Human-readable price range built from PlacePricing, e.g. "KES 2,000–5,000".
  /// Returns null when pricing is absent.
  String? get priceRange {
    final p = pricing;
    if (p == null) return null;
    final currency = p.currency;
    if (p.min != null && p.max != null) {
      return '$currency ${_fmtPrice(p.min!)}–${_fmtPrice(p.max!)}';
    }
    if (p.min != null) return 'From $currency ${_fmtPrice(p.min!)}';
    if (p.max != null) return 'Up to $currency ${_fmtPrice(p.max!)}';
    return null;
  }

  /// Feature / amenity list from taxonomy tags.
  List<String> get features => List<String>.unmodifiable(taxonomy);
}

String _fmtPrice(double v) =>
    v.truncateToDouble() == v ? v.toInt().toString() : v.toStringAsFixed(0);

class PlaceCard extends StatelessWidget {
  final PlaceModel place;

  /// Shown when the place has no linked category of its own (e.g. browsed
  /// directly from a city's "All Listings" tab rather than through a
  /// specific category).
  final String fallbackCategoryName;

  final VoidCallback onTap;

  const PlaceCard({
    super.key,
    required this.place,
    required this.fallbackCategoryName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: PlaceCardColors.deepBlue,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: PlaceCardColors.aqua.withValues(alpha: 0.20), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.40),
              blurRadius: 16,
              spreadRadius: 2,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image section with overlay badges
              _buildPlaceImage(),

              // Text summary
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name + rating
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            place.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        // Rating from attributes['rating'] via extension
                        if (place.rating != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFB300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star,
                                    size: 14, color: Colors.white),
                                const SizedBox(width: 4),
                                Text(
                                  place.rating!.toStringAsFixed(1),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Category name · review count
                    Row(
                      children: [
                        Text(
                          // primaryCategoryName from extension (categoryLinks.first)
                          place.primaryCategoryName ?? fallbackCategoryName,
                          style: const TextStyle(
                            fontSize: 13,
                            color: PlaceCardColors.aquaBright,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        // reviewCount from attributes['reviewCount'] via extension
                        if ((place.reviewCount ?? 0) > 0) ...[
                          const SizedBox(width: 8),
                          Text('•',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5))),
                          const SizedBox(width: 8),
                          Text(
                            '${place.reviewCount} reviews',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.70),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Description
                    if ((place.description ?? '').isNotEmpty) ...[
                      Text(
                        place.description!,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.80),
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Feature chips from taxonomy via extension
                    if (place.features.isNotEmpty) ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: place.features.take(4).map((f) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.20)),
                            ),
                            child: Text(f,
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.white70)),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // View Details button
                    SizedBox(
                      width: double.infinity,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              PlaceCardColors.aquaBright,
                              PlaceCardColors.aqua
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  PlaceCardColors.aqua.withValues(alpha: 0.40),
                              blurRadius: 10,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'View Details',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(Icons.arrow_forward,
                                color: Colors.white, size: 16),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Place image with Open/Closed and price badges ─────────────────────────
  Widget _buildPlaceImage() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final imageH = constraints.maxWidth * 0.55;
        return SizedBox(
          height: imageH,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Cover image (network) or initials fallback
              if ((place.coverImage ?? '').isNotEmpty)
                Image.network(
                  place.coverImage!,
                  fit: BoxFit.cover,
                  frameBuilder: (ctx, child, frame, _) => AnimatedOpacity(
                    opacity: frame == null ? 0.0 : 1.0,
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOut,
                    child: child,
                  ),
                  errorBuilder: (_, __, ___) => _imageFallback(),
                )
              else
                _imageFallback(),

              // Bottom gradient scrim
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.55),
                      ],
                    ),
                  ),
                ),
              ),

              // Open / Closed badge — derived from attributes['isOpen']
              // Only shown when the attribute is explicitly set.
              if (place.isOpen != null)
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: place.isOpen! ? Colors.green : Colors.red,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      place.isOpen! ? 'Open' : 'Closed',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

              // Price range badge — derived from place.pricing via extension
              if ((place.priceRange ?? '').isNotEmpty)
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.60),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      place.priceRange!,
                      style: const TextStyle(
                        color: PlaceCardColors.aquaBright,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _imageFallback() => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              PlaceCardColors.aqua.withValues(alpha: 0.35),
              PlaceCardColors.deepBlue,
            ],
          ),
        ),
        child: Center(
          child: Text(
            place.name.isNotEmpty ? place.name[0].toUpperCase() : '?',
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: Colors.white.withValues(alpha: 0.35),
            ),
          ),
        ),
      );
}
