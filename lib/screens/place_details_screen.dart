import 'package:flutter/material.dart';
import 'package:palmnazi/models/models.dart';

// ── Shared palette ───────────────────────────────────────────────────────────
abstract final class _P {
  static const Color aquaBright = Color(0xFF00E5FF);
  static const Color aqua       = Color(0xFF00B8D4);
  static const Color amber      = Color(0xFFFFB300);
  static const Color deepNavy   = Color(0xFF01263F);
}

class PlaceDetailsScreen extends StatefulWidget {
  final ResortCityItem city;
  final ChannelItem    channel;
  final PlaceItem      place;

  const PlaceDetailsScreen({
    super.key,
    required this.city,
    required this.channel,
    required this.place,
  });

  @override
  State<PlaceDetailsScreen> createState() => _PlaceDetailsScreenState();
}

class _PlaceDetailsScreenState extends State<PlaceDetailsScreen>
    with TickerProviderStateMixin {
  late ScrollController _scrollController;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  double _scrollOffset = 0;

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
          // ── Static place image as full-screen background ──────────────────
          Positioned.fill(
            child: Image.asset(
              widget.place.assetPath,
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

          // Dark scrim for text readability
          Positioned.fill(
            child: Container(color: Colors.black.withValues(alpha: 0.52)),
          ),

          // ── Scrollable content ────────────────────────────────────────────
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              // Space for top nav
              const SliverToBoxAdapter(child: SizedBox(height: 80)),

              // Main content
              SliverToBoxAdapter(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Breadcrumb
                      _buildBreadcrumb(),

                      // Place info card — first visible content after breadcrumb
                      _buildPlaceInfoCard(),

                      // Quick actions
                      _buildQuickActions(),

                      // Description
                      _buildDescriptionSection(),

                      // Features
                      _buildFeaturesSection(),

                      // Contact
                      _buildContactSection(),

                      // Reviews
                      _buildReviewsSection(),

                      // Action buttons
                      _buildActionButtons(),

                      const SizedBox(height: 48),
                    ],
                  ),
                ),
              ),
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
    final navOpacity = (_scrollOffset / 80).clamp(0.0, 1.0);
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
                      colors: [_P.aquaBright, _P.aqua],
                    ),
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

                // Place name pill
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: widget.channel.color.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      widget.place.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            widget.city.name,
            style: TextStyle(
              color: widget.city.color,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          Icon(Icons.chevron_right,
              size: 16, color: Colors.white.withValues(alpha: 0.50)),
          Text(
            widget.channel.title,
            style: TextStyle(
              color: widget.channel.color,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          Icon(Icons.chevron_right,
              size: 16, color: Colors.white.withValues(alpha: 0.50)),
          Text(
            widget.place.name,
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

  // ── Place info card ───────────────────────────────────────────────────────
  Widget _buildPlaceInfoCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            widget.channel.color.withValues(alpha: 0.30),
            widget.channel.color.withValues(alpha: 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: widget.channel.color.withValues(alpha: 0.50)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.place.name,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.place.category,
                      style: TextStyle(
                        fontSize: 16,
                        color: widget.channel.color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: widget.place.isOpen ? Colors.green : Colors.red,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  widget.place.isOpen ? 'Open Now' : 'Closed',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _P.amber,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.star, size: 18, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(
                      widget.place.rating.toString(),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${widget.place.reviewCount} reviews',
                style: const TextStyle(
                    fontSize: 14, color: Colors.white70),
              ),
              const Spacer(),
              Text(
                widget.place.priceRange,
                style: const TextStyle(
                  fontSize: 20,
                  color: _P.aquaBright,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Quick actions ─────────────────────────────────────────────────────────
  Widget _buildQuickActions() {
    return Container(
      margin: const EdgeInsets.all(24),
      child: Row(
        children: [
          Expanded(
              child: _buildQuickActionButton(
                  Icons.phone, 'Call', widget.channel.color)),
          const SizedBox(width: 12),
          Expanded(
              child: _buildQuickActionButton(
                  Icons.directions, 'Directions', const Color(0xFF2979FF))),
          const SizedBox(width: 12),
          Expanded(
              child: _buildQuickActionButton(
                  Icons.language, 'Website', const Color(0xFFAA00FF))),
          const SizedBox(width: 12),
          Expanded(
              child: _buildQuickActionButton(
                  Icons.share, 'Share', const Color(0xFF00BFA5))),
        ],
      ),
    );
  }

  Widget _buildQuickActionButton(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.50)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ── Description ───────────────────────────────────────────────────────────
  Widget _buildDescriptionSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'About',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 12),
          Text(
            widget.place.description,
            style: const TextStyle(
                fontSize: 15, color: Colors.white70, height: 1.6),
          ),
        ],
      ),
    );
  }

  // ── Features ──────────────────────────────────────────────────────────────
  Widget _buildFeaturesSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Features & Amenities',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: widget.place.features.map((feature) {
              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      widget.channel.color.withValues(alpha: 0.30),
                      widget.channel.color.withValues(alpha: 0.10),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: widget.channel.color.withValues(alpha: 0.50)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle,
                        size: 16, color: _P.aquaBright),
                    const SizedBox(width: 8),
                    Text(
                      feature,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── Contact ───────────────────────────────────────────────────────────────
  Widget _buildContactSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Contact Information',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white),
          ),
          const SizedBox(height: 16),
          _buildContactItem(
              Icons.location_on, 'Address', widget.place.address),
          const SizedBox(height: 12),
          _buildContactItem(Icons.phone, 'Phone', widget.place.phone),
          const SizedBox(height: 12),
          _buildContactItem(
              Icons.language, 'Website', widget.place.website),
        ],
      ),
    );
  }

  Widget _buildContactItem(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _P.aquaBright, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white54,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(value,
                  style: const TextStyle(
                      fontSize: 14, color: Colors.white)),
            ],
          ),
        ),
      ],
    );
  }

  // ── Reviews ───────────────────────────────────────────────────────────────
  Widget _buildReviewsSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Reviews',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
              TextButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Full reviews feature coming soon!'),
                      backgroundColor: Color(0xFF006064),
                    ),
                  );
                },
                child: const Text(
                  'See All',
                  style: TextStyle(
                      color: _P.aquaBright, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Reviews feature will be integrated with backend',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.60),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  // ── Action buttons ────────────────────────────────────────────────────────
  Widget _buildActionButtons() {
    return Container(
      margin: const EdgeInsets.all(24),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Booking feature coming soon!'),
                    backgroundColor: Color(0xFF006064),
                  ),
                );
              },
              icon: const Icon(Icons.calendar_today, size: 20),
              label: const Text(
                'Book Now',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _P.aquaBright,
                foregroundColor: _P.deepNavy,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 4,
                shadowColor: _P.aqua.withValues(alpha: 0.50),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: _P.aquaBright, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Favourites feature coming soon!'),
                    backgroundColor: Color(0xFF006064),
                  ),
                );
              },
              icon: const Icon(Icons.favorite_border,
                  color: _P.aquaBright, size: 24),
              padding: const EdgeInsets.all(12),
            ),
          ),
        ],
      ),
    );
  }
}