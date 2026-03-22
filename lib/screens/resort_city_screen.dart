import 'package:flutter/material.dart';
import 'package:palmnazi/screens/auth_screen.dart';
import 'package:palmnazi/screens/channel_screen.dart';
import 'package:palmnazi/widgets/animated_background.dart';
import 'package:palmnazi/widgets/robust_asset_image.dart';
import 'package:palmnazi/models/models.dart';

// ── Shared palette (mirrors landing_page.dart PalmColors) ───────────────────
abstract final class _P {
  static const Color aqua       = Color(0xFF00B8D4);
  static const Color aquaBright = Color(0xFF00E5FF);
  static const Color deepNavy   = Color(0xFF01263F);
}

class ResortCityScreen extends StatefulWidget {
  final ResortCityItem city;

  const ResortCityScreen({
    super.key,
    required this.city,
  });

  @override
  State<ResortCityScreen> createState() => _ResortCityScreenState();
}

class _ResortCityScreenState extends State<ResortCityScreen>
    with TickerProviderStateMixin {
  late ScrollController _scrollController;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  double _scrollOffset = 0;

  // ── Vivid channel colours — bright, each category distinct ─────────────────
  final List<ChannelItem> _channels = [
    ChannelItem(
      id: '1',
      icon: Icons.king_bed_outlined,
      title: 'Accommodation',
      description: 'Premium stays and luxury lodging',
      color: const Color(0xFF00ACC1), // vivid cyan
      imagePath: 'channels/accommodation.jpg',
      subcategories: [
        'Luxury Hotels', 'Beach Resorts', 'Mountain Lodges',
        'Boutique Hotels', 'Vacation Rentals', 'Eco-Lodges',
      ],
    ),
    ChannelItem(
      id: '2',
      icon: Icons.restaurant_menu,
      title: 'Dining',
      description: 'Culinary experiences and local cuisine',
      color: const Color(0xFFF50057), // vivid pink-red
      imagePath: 'channels/dining.jpg',
      subcategories: [
        'Fine Dining', 'Local Cuisine', 'Seafood Restaurants',
        'Street Food', 'Cafes & Coffee Shops', 'Rooftop Bars',
      ],
    ),
    ChannelItem(
      id: '3',
      icon: Icons.celebration,
      title: 'Events',
      description: 'Festivals and cultural experiences',
      color: const Color(0xFFFF6D00), // vivid deep orange
      imagePath: 'channels/events.jpg',
      subcategories: [
        'Music Festivals', 'Cultural Ceremonies', 'Art Exhibitions',
        'Food Festivals', 'Sports Events', 'Night Markets',
      ],
    ),
    ChannelItem(
      id: '4',
      icon: Icons.shopping_bag_outlined,
      title: 'Shopping',
      description: 'Markets and artisan crafts',
      color: const Color(0xFFAA00FF), // vivid purple
      imagePath: 'channels/shopping.jpg',
      subcategories: [
        'Artisan Markets', 'Shopping Malls', 'Craft Stores',
        'Jewelry Shops', 'Textile Markets', 'Souvenir Shops',
      ],
    ),
    ChannelItem(
      id: '5',
      icon: Icons.terrain,
      title: 'Adventure',
      description: 'Nature and outdoor activities',
      color: const Color(0xFF2979FF), // electric blue
      imagePath: 'channels/adventure.jpg',
      subcategories: [
        'Safari Tours', 'Hiking Trails', 'Water Sports',
        'Wildlife Viewing', 'Beach Activities', 'Mountain Climbing',
      ],
    ),
    ChannelItem(
      id: '6',
      icon: Icons.spa_outlined,
      title: 'Wellness',
      description: 'Relaxation and rejuvenation',
      color: const Color(0xFF00BFA5), // vivid teal-green
      imagePath: 'channels/wellness.jpg',
      subcategories: [
        'Spa & Massage', 'Yoga Retreats', 'Wellness Centers',
        'Hot Springs', 'Meditation Gardens', 'Fitness Centers',
      ],
    ),
  ];

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

  void _navigateToChannel(ChannelItem channel) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChannelScreen(city: widget.city, channel: channel),
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
          // Animated background — keeps motion effects on inner screens
          const AnimatedBackground(),

          // Main scrollable content
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              // Space below the custom top nav bar
              const SliverToBoxAdapter(child: SizedBox(height: 70)),

              // ── City hero image + info ──────────────────────────────────
              SliverToBoxAdapter(child: _buildCityHero()),

              // ── City info card ─────────────────────────────────────────
              SliverToBoxAdapter(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: _buildCityInfo(),
                ),
              ),

              // ── "Explore Channels" heading ─────────────────────────────
              SliverToBoxAdapter(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: _buildChannelsHeading(),
                ),
              ),

              // ── Channels grid ──────────────────────────────────────────
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 400,
                    childAspectRatio: 1.0,
                    crossAxisSpacing: 20,
                    mainAxisSpacing: 20,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => FadeTransition(
                      opacity: _fadeAnimation,
                      child: _buildChannelCard(_channels[index]),
                    ),
                    childCount: _channels.length,
                  ),
                ),
              ),

              // ── Footer ────────────────────────────────────────────────
              SliverToBoxAdapter(child: _buildFooter()),
            ],
          ),

          // ── Custom top nav bar ─────────────────────────────────────────
          _buildTopNav(),
        ],
      ),
    );
  }

  // ── Top nav bar — matches landing page style ─────────────────────────────
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // ── Left: back arrow + PALMNAZI brand ─────────────────────
                Row(
                  children: [
                    // Back button
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.15),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.30),
                          ),
                        ),
                        child: const Icon(
                          Icons.arrow_back,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Logo orb
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [_P.aquaBright, _P.aqua],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _P.aqua.withValues(alpha: 0.55),
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.landscape, color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 10),

                    // Brand name
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [_P.aquaBright, Colors.white],
                      ).createShader(bounds),
                      child: const Text(
                        'PALMNAZI',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ],
                ),

                // ── Right: Sign In | Blog | Get Started ───────────────────
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const AuthScreen(isLogin: true))),
                      child: const Text(
                        'Sign In',
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        // Navigate to Blog screen
                      },
                      child: const Text(
                        'Blog',
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ),
                    const SizedBox(width: 4),
                    ElevatedButton(
                      onPressed: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const AuthScreen(isLogin: false))),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _P.aquaBright,
                        foregroundColor: _P.deepNavy,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        elevation: 4,
                        shadowColor: _P.aqua.withValues(alpha: 0.50),
                      ),
                      child: const Text(
                        'Get Started',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── City hero image ───────────────────────────────────────────────────────
  Widget _buildCityHero() {
    return SizedBox(
      height: 280,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RobustAssetImage(
            imagePath: widget.city.assetPath,
            fit: BoxFit.cover,
            fallbackColor: widget.city.color,
            fallbackIcon: Icons.location_city,
          ),
          // Bottom gradient for text legibility
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.10),
                  Colors.black.withValues(alpha: 0.68),
                ],
              ),
            ),
          ),
          // City name overlay
          Positioned(
            bottom: 24, left: 24, right: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.city.name,
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 1,
                    shadows: [Shadow(color: Colors.black45, blurRadius: 12)],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.city.tagline,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: widget.city.color,
                    shadows: const [Shadow(color: Colors.black38, blurRadius: 8)],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── City info card ────────────────────────────────────────────────────────
  Widget _buildCityInfo() {
    return Container(
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            widget.city.color.withValues(alpha: 0.25),
            widget.city.color.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: widget.city.color.withValues(alpha: 0.45),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.city.name,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.city.tagline,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: widget.city.color,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            widget.city.description,
            style: TextStyle(
              fontSize: 15,
              color: Colors.white.withValues(alpha: 0.88),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          // Highlights
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.city.highlights.map((h) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: widget.city.color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: widget.city.color.withValues(alpha: 0.55), width: 1.2),
              ),
              child: Text(
                h,
                style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600),
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }

  // ── Channels heading ──────────────────────────────────────────────────────
  Widget _buildChannelsHeading() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [_P.aquaBright, Colors.white],
            ).createShader(bounds),
            child: Text(
              'Explore Channels',
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Choose a category to discover amazing places and experiences',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.80),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── Channel card ──────────────────────────────────────────────────────────
  Widget _buildChannelCard(ChannelItem channel) {
    return GestureDetector(
      onTap: () => _navigateToChannel(channel),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: channel.color.withValues(alpha: 0.50),
              blurRadius: 18,
              spreadRadius: 2,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              // Background image
              Positioned.fill(
                child: RobustAssetImage(
                  imagePath: channel.assetPath,
                  fit: BoxFit.cover,
                  fallbackColor: channel.color,
                  fallbackIcon: channel.icon,
                ),
              ),

              // Gradient overlay — lighter at top, darker at bottom
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.15),
                        Colors.black.withValues(alpha: 0.78),
                      ],
                    ),
                  ),
                ),
              ),

              // Card content
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Icon orb — channel-coloured border
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: channel.color.withValues(alpha: 0.25),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: channel.color.withValues(alpha: 0.80),
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: channel.color.withValues(alpha: 0.35),
                              blurRadius: 12,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Icon(channel.icon, size: 32, color: Colors.white),
                      ),
                      const SizedBox(height: 16),

                      // Title
                      Text(
                        channel.title,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Description
                      Text(
                        channel.description,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.88),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 14),

                      // Explore pill — channel-accented
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: channel.color,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: channel.color.withValues(alpha: 0.55),
                              blurRadius: 10,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Explore',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            SizedBox(width: 6),
                            Icon(Icons.arrow_forward, size: 14, color: Colors.white),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Footer ────────────────────────────────────────────────────────────────
  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.70),
          ],
        ),
      ),
      child: Column(
        children: [
          // City colour accent divider
          Container(
            height: 2,
            margin: const EdgeInsets.only(bottom: 28),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  widget.city.color,
                  Colors.transparent,
                ],
              ),
            ),
          ),

          // Nav links
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: ['About', 'Contact', 'Privacy', 'Terms']
                .map((t) => TextButton(
                      onPressed: () {},
                      child: Text(
                        t,
                        style: const TextStyle(
                          color: _P.aquaBright,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ))
                .toList(),
          ),

          const SizedBox(height: 16),

          Text(
            '© 2026 Palmnazi Resort Cities. All rights reserved.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}