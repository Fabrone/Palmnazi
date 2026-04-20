import 'package:flutter/material.dart';
import 'package:palmnazi/screens/place_details_screen.dart';
import 'package:palmnazi/widgets/robust_asset_image.dart';
import 'package:palmnazi/models/models.dart';

// ── Shared palette ───────────────────────────────────────────────────────────
abstract final class _P {
  static const Color aquaBright = Color(0xFF00E5FF);
  static const Color aqua       = Color(0xFF00B8D4);
  static const Color deepNavy   = Color(0xFF01263F);
}

class ChannelScreen extends StatefulWidget {
  final ResortCityItem city;
  final ChannelItem channel;

  const ChannelScreen({
    super.key,
    required this.city,
    required this.channel,
  });

  @override
  State<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends State<ChannelScreen>
    with TickerProviderStateMixin {
  late ScrollController _scrollController;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  String? _selectedSubcategory;
  double _scrollOffset = 0;

  final List<PlaceItem> _places = [
    PlaceItem(
      id: '1',
      name: 'Serena Beach Resort & Spa',
      category: 'Luxury Hotels',
      rating: 4.8,
      reviewCount: 342,
      description: 'Experience ultimate luxury at this 5-star beachfront resort with world-class amenities and breathtaking ocean views.',
      imagePath: 'places/serena_beach.jpg',
      address: 'Shanzu Beach, North Coast',
      phone: '+254 712 345 678',
      website: 'www.serenabeach.com',
      features: ['Beach Access', 'Spa', 'Pool', 'Restaurant', 'Wi-Fi', 'Parking'],
      priceRange: '\$\$\$\$',
      isOpen: true,
    ),
    PlaceItem(
      id: '2',
      name: 'Voyager Beach Resort',
      category: 'Beach Resorts',
      rating: 4.6,
      reviewCount: 289,
      description: 'All-inclusive beach resort with exciting activities, entertainment, and family-friendly facilities.',
      imagePath: 'places/voyager.jpg',
      address: 'Nyali Beach Road',
      phone: '+254 712 345 679',
      website: 'www.voyagerbeach.com',
      features: ['All-Inclusive', 'Kids Club', 'Water Sports', 'Entertainment', 'Pool'],
      priceRange: '\$\$\$',
      isOpen: true,
    ),
    PlaceItem(
      id: '3',
      name: 'Bamburi Beach Hotel',
      category: 'Beach Resorts',
      rating: 4.5,
      reviewCount: 215,
      description: 'Comfortable beachfront hotel with excellent service and stunning sunset views.',
      imagePath: 'places/bamburi.jpg',
      address: 'Bamburi Beach',
      phone: '+254 712 345 680',
      website: 'www.bamburibeach.com',
      features: ['Beach Access', 'Restaurant', 'Bar', 'Pool', 'Wi-Fi'],
      priceRange: '\$\$',
      isOpen: true,
    ),
  ];

  List<PlaceItem> get filteredPlaces {
    if (_selectedSubcategory == null) return _places;
    return _places.where((p) => p.category == _selectedSubcategory).toList();
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeIn),
    );
    _fadeController.forward();
  }

  void _onScroll() => setState(() => _scrollOffset = _scrollController.offset);

  void _navigateToPlaceDetails(PlaceItem place) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlaceDetailsScreen(
          city: widget.city,
          channel: widget.channel,
          place: place,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  // ════════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ── Static channel image as full-screen background ────────────────
          Positioned.fill(
            child: Image.asset(
              widget.channel.assetPath,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [widget.channel.color, Colors.black],
                  ),
                ),
              ),
            ),
          ),

          // Scrim for readability
          Positioned.fill(
            child: Container(color: Colors.black.withValues(alpha: 0.50)),
          ),

          // ── Scrollable content ────────────────────────────────────────────
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 80)),
              SliverToBoxAdapter(child: _buildBreadcrumb()),
              SliverToBoxAdapter(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: _buildChannelDescription(),
                ),
              ),
              SliverToBoxAdapter(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: _buildSubcategoryFilter(),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 8),
                  child: Text(
                    '${filteredPlaces.length} '
                    '${filteredPlaces.length == 1 ? 'place' : 'places'} found',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.80),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => FadeTransition(
                      opacity: _fadeAnimation,
                      child: _buildPlaceCard(filteredPlaces[index]),
                    ),
                    childCount: filteredPlaces.length,
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 48)),
            ],
          ),

          // ── Top nav bar ────────────────────────────────────────────────────
          _buildTopNav(),
        ],
      ),
    );
  }

  // ── Top nav bar ───────────────────────────────────────────────────────────
  Widget _buildTopNav() {
    final double navOpacity = (_scrollOffset / 80).clamp(0.0, 1.0);
    return Positioned(
      top: 0, left: 0, right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.30 + 0.45 * navOpacity),
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // Back
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.15),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.30)),
                    ),
                    child: const Icon(Icons.arrow_back,
                        color: Colors.white, size: 18),
                  ),
                ),
                const SizedBox(width: 10),
                // Logo orb
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                        colors: [_P.aquaBright, _P.aqua]),
                    boxShadow: [
                      BoxShadow(
                          color: _P.aqua.withValues(alpha: 0.50),
                          blurRadius: 10),
                    ],
                  ),
                  child: const Icon(Icons.landscape,
                      color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                // Brand name
                ShaderMask(
                  shaderCallback: (b) => const LinearGradient(
                    colors: [_P.aquaBright, Colors.white],
                  ).createShader(b),
                  child: const Text(
                    'PALMNAZI',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                const Spacer(),
                // Channel title pill
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: widget.channel.color.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(widget.channel.icon,
                          color: Colors.white, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        widget.channel.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Breadcrumb ────────────────────────────────────────────────────────────
  Widget _buildBreadcrumb() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          Text(
            widget.city.name,
            style: TextStyle(
              color: widget.city.color,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right,
              size: 16, color: Colors.white.withValues(alpha: 0.5)),
          const SizedBox(width: 8),
          Text(
            widget.channel.title,
            style: const TextStyle(
              color: _P.aquaBright,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ── Channel description card ──────────────────────────────────────────────
  Widget _buildChannelDescription() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            widget.channel.color.withValues(alpha: 0.30),
            widget.channel.color.withValues(alpha: 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: widget.channel.color.withValues(alpha: 0.50)),
      ),
      child: Text(
        widget.channel.description,
        style: TextStyle(
          fontSize: 14,
          color: Colors.white.withValues(alpha: 0.90),
          height: 1.5,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  // ── Subcategory filter ────────────────────────────────────────────────────
  Widget _buildSubcategoryFilter() {
    return SizedBox(
      height: 50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        children: [
          _buildFilterChip('All', null),
          const SizedBox(width: 12),
          ...widget.channel.subcategories.map((s) => Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _buildFilterChip(s, s),
              )),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String? value) {
    final bool isSelected = _selectedSubcategory == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedSubcategory = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  colors: [_P.aquaBright, widget.channel.color])
              : null,
          color: isSelected ? null : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
            color: isSelected
                ? Colors.transparent
                : Colors.white.withValues(alpha: 0.30),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? _P.deepNavy : Colors.white,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  // ── Place card ────────────────────────────────────────────────────────────
  Widget _buildPlaceCard(PlaceItem place) {
    return GestureDetector(
      onTap: () => _navigateToPlaceDetails(place),
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: Colors.white.withValues(alpha: 0.08),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(
              color: widget.channel.color.withValues(alpha: 0.20),
              blurRadius: 12,
              spreadRadius: 1,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Image section: 3-column layout — centre holds the image ──
              // left spacer | square image | right spacer
              // LayoutBuilder reads the card width so the image scales
              // proportionally: ~45 % of card width, clamped 120–190 px.
              LayoutBuilder(
                builder: (context, constraints) {
                  final double imgSize =
                      (constraints.maxWidth * 0.45).clamp(120.0, 190.0);

                  return Stack(
                    alignment: Alignment.topCenter,
                    children: [
                      // Row: spacer | image | spacer
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Expanded(child: SizedBox()),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                width: imgSize,
                                height: imgSize,
                                color: Colors.black.withValues(alpha: 0.20),
                                child: RobustAssetImage(
                                  imagePath: place.assetPath,
                                  fit: BoxFit.contain,
                                  fallbackColor: widget.channel.color,
                                  fallbackIcon: widget.channel.icon,
                                ),
                              ),
                            ),
                            const Expanded(child: SizedBox()),
                          ],
                        ),
                      ),

                      // Open / Closed badge — floats top-right of the section
                      Positioned(
                        top: 12, right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: place.isOpen ? Colors.green : Colors.red,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            place.isOpen ? 'Open' : 'Closed',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),

                      // Price badge — floats top-left of the section
                      Positioned(
                        top: 12, left: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.60),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            place.priceRange,
                            style: const TextStyle(
                              color: _P.aquaBright,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ], // Stack children
                  ); // Stack
                }, // builder
              ), // LayoutBuilder

              // ── Place summary ─────────────────────────────────────────────
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
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFB300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.star,
                                  size: 14, color: Colors.white),
                              const SizedBox(width: 4),
                              Text(
                                place.rating.toString(),
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

                    // Category · reviews
                    Row(
                      children: [
                        Text(
                          place.category,
                          style: TextStyle(
                            fontSize: 13,
                            color: widget.channel.color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '•',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5)),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${place.reviewCount} reviews',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.70),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Description
                    Text(
                      place.description,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.80),
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),

                    // Feature chips
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
                          child: Text(
                            f,
                            style: const TextStyle(
                                fontSize: 11, color: Colors.white70),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    // View Details button
                    SizedBox(
                      width: double.infinity,
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [_P.aquaBright, widget.channel.color],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: _P.aqua.withValues(alpha: 0.40),
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
            ], // Column children
          ), // Column
        ), // ClipRRect
      ), // Container
    ); // GestureDetector
  }
}