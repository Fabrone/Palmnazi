import 'package:flutter/material.dart';
import 'package:palmnazi/admin/admin_dashboard.dart';
import 'package:palmnazi/screens/auth_screen.dart';
import 'package:palmnazi/screens/resort_city_screen.dart';
import 'package:palmnazi/widgets/stats_counter.dart';
import 'package:palmnazi/models/models.dart';
import 'package:palmnazi/widgets/robust_asset_image.dart';
import 'dart:async';

// ════════════════════════════════════════════════════════════════════════════
//  PALMNAZI COLOUR SYSTEM
// ════════════════════════════════════════════════════════════════════════════
abstract final class PalmColors {
  static const Color aqua        = Color(0xFF00B8D4);
  static const Color aquaBright  = Color(0xFF00E5FF);
  static const Color amber       = Color(0xFFFFB300);
  static const Color deepNavy    = Color.fromARGB(255, 33, 2, 60);
  static const Color mombasaCoral = Color.fromRGBO(41, 5, 83, 1); // near-black burnt coral
  static const Color malindiBlue  = Color.fromARGB(255, 2, 32, 76); // near-black navy
  static const Color dianiGreen   = Color(0xFF0A2E0D); // near-black forest green
}

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage>
    with TickerProviderStateMixin {
  late ScrollController _scrollController;
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _logoController;
  late AnimationController _nameController;
  late AnimationController _logoExitController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _logoScaleAnimation;
  late Animation<double> _nameFadeAnimation;
  late Animation<Offset> _logoExitAnimation;

  double _scrollOffset = 0;
  bool _showMainContent = false;

  // ── Search form state ────────────────────────────────────────────────────
  final TextEditingController _searchController = TextEditingController();
  DateTime? _checkInDate;
  DateTime? _checkOutDate;
  int _adultCount  = 1;
  int _childCount  = 0;

  final List<ResortCityItem> _resortCities = [
    ResortCityItem(
      id: '1',
      name: 'Mombasa',
      tagline: 'The Coastal Paradise',
      description: 'Experience pristine beaches, rich Swahili culture, and world-class resorts along the Indian Ocean coastline.',
      imagePath: 'cities/mombasa.jpg',
      color: PalmColors.mombasaCoral,
      highlights: ['Pristine Beaches', 'Water Sports', 'Cultural Heritage', 'Luxury Resorts'],
    ),
    ResortCityItem(
      id: '2',
      name: 'Malindi',
      tagline: 'Where History Meets the Sea',
      description: 'Discover ancient ruins, marine parks, and serene coastal beauty in this historic coastal town.',
      imagePath: 'cities/malindi.jpg',
      color: PalmColors.malindiBlue,
      highlights: ['Marine Parks', 'Historic Sites', 'Beach Resorts', 'Water Activities'],
    ),
    ResortCityItem(
      id: '3',
      name: 'Diani Beach',
      tagline: 'Tropical Heaven on Earth',
      description: 'Indulge in powder-white sand beaches, crystal-clear waters, and luxury beachfront accommodations.',
      imagePath: 'cities/diani.jpg',
      color: PalmColors.dianiGreen,
      highlights: ['White Sand Beaches', 'Diving & Snorkeling', 'Luxury Villas', 'Nightlife'],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);

    _fadeController     = AnimationController(duration: const Duration(milliseconds: 500),  vsync: this);
    _slideController    = AnimationController(duration: const Duration(milliseconds: 400),  vsync: this);
    _logoController     = AnimationController(duration: const Duration(milliseconds: 2800), vsync: this);
    _nameController     = AnimationController(duration: const Duration(milliseconds: 500),  vsync: this);
    _logoExitController = AnimationController(duration: const Duration(milliseconds: 600),  vsync: this);

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut));

    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));

    _logoScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.5, end: 1.1).chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.1, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 60,
      ),
    ]).animate(_logoController);

    _nameFadeAnimation = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _nameController, curve: Curves.easeIn));

    _logoExitAnimation = Tween<Offset>(begin: Offset.zero, end: const Offset(0, -2.5))
        .animate(CurvedAnimation(parent: _logoExitController, curve: Curves.easeInOut));

    _startIntroAnimation();
  }

  void _startIntroAnimation() async {
    _logoController.forward();
    await Future.delayed(const Duration(milliseconds: 3000));
    if (!mounted) return;
    _nameController.forward();
    await Future.delayed(const Duration(milliseconds: 2000));
    if (!mounted) return;
    _logoExitController.forward();
    await Future.delayed(const Duration(milliseconds: 350));
    if (mounted) {
      setState(() => _showMainContent = true);
      _fadeController.forward();
      _slideController.forward();
      Timer(const Duration(milliseconds: 400), _scrollToCities);
    }
  }

  void _scrollToCities() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(10.0,
          duration: const Duration(milliseconds: 1200),
          curve: Curves.easeInOutCubic);
    }
  }

  void _onScroll() => setState(() => _scrollOffset = _scrollController.offset);

  void _navigateToCity(ResortCityItem city) {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => ResortCityScreen(city: city)));
  }

  // ── Search handler ────────────────────────────────────────────────────────
  // Matches the query against city names / taglines / highlights.
  // Falls back to the first city. Lands on ResortCityScreen — the correct
  // entry point — because ChannelScreen requires both a city AND a channel
  // object that are only known after the user picks from that list.
  void _handleSearch() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return;

    final matched = _resortCities.firstWhere(
      (c) =>
          c.name.toLowerCase().contains(query) ||
          c.tagline.toLowerCase().contains(query) ||
          c.highlights.any((h) => h.toLowerCase().contains(query)),
      orElse: () => _resortCities.first,
    );

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ResortCityScreen(city: matched)),
    );
  }

  // ── Date-picker helper ────────────────────────────────────────────────────
  Future<void> _pickDate({required bool isCheckIn}) async {
    final now   = DateTime.now();
    final first = isCheckIn ? now : (_checkInDate ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: first,
      firstDate: first,
      lastDate: DateTime(now.year + 2),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary:   PalmColors.aquaBright,
              onPrimary: PalmColors.deepNavy,
              surface:   Color(0xFF01263F),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      setState(() {
        if (isCheckIn) {
          _checkInDate = picked;
          // Reset check-out if it's now before check-in
          if (_checkOutDate != null && _checkOutDate!.isBefore(picked)) {
            _checkOutDate = null;
          }
        } else {
          _checkOutDate = picked;
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    _logoController.dispose();
    _nameController.dispose();
    _logoExitController.dispose();
    super.dispose();
  }

  // ════════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Static hero background — no animated particles/overlays on landing page
          Positioned.fill(
            child: Image.asset(
              'assets/images/hero_background.png',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF006064), Color(0xFF01579B)],
                  ),
                ),
              ),
            ),
          ),
          // Thin dark scrim for readability over the hero image
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.35),
            ),
          ),
          if (!_showMainContent) _buildIntroScreen() else _buildMainContent(),
          if (_showMainContent) _buildAppBar(),
        ],
      ),
    );
  }

  // ── App Bar ──────────────────────────────────────────────────────────────
  // CHANGE 5: Added "Blog" TextButton between Sign In and Get Started

  Widget _buildAppBar() {
    final opacity = (_scrollOffset / 100).clamp(0.0, 1.0);
    return Positioned(
      top: 0, left: 0, right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.55 * opacity),
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
                // ── Left: logo orb + brand name
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const AdminDashboard())),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [PalmColors.aquaBright, PalmColors.aqua],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: PalmColors.aqua.withValues(alpha: 0.55),
                              blurRadius: 14,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.landscape, color: Colors.white, size: 22),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [PalmColors.aquaBright, Colors.white],
                      ).createShader(bounds),
                      child: const Text(
                        'PALMNAZI',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ],
                ),

                // ── Right: Sign In | Blog | Get Started
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const AuthScreen(isLogin: true))),
                      child: const Text(
                        'Sign In',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    // ── NEW: Blog button ─────────────────────────────────
                    TextButton(
                      onPressed: () {
                        // Navigate to Blog screen — route to be wired up
                      },
                      child: const Text(
                        'Blog',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    ElevatedButton(
                      onPressed: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const AuthScreen(isLogin: false))),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: PalmColors.aquaBright,
                        foregroundColor: PalmColors.deepNavy,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                        elevation: 4,
                        shadowColor: PalmColors.aqua.withValues(alpha: 0.50),
                      ),
                      child: const Text('Get Started',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
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

  // ── Intro / Splash ───────────────────────────────────────────────────────
  // CHANGE 4: Logo orb Container decoration removed — bare logo image only

  Widget _buildIntroScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Logo — no wrapping Container, no gradient circle, no shadows
          AnimatedBuilder(
            animation: Listenable.merge([_logoScaleAnimation, _logoExitAnimation]),
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(
                    0, _logoExitAnimation.value.dy * MediaQuery.of(context).size.height),
                child: Transform.scale(
                  scale: _logoScaleAnimation.value,
                  child: RobustAssetImage(
                    imagePath: 'logo.png',
                    width: 130,
                    height: 130,
                    fit: BoxFit.contain,
                    fallbackIcon: Icons.landscape,
                    fallbackColor: PalmColors.aquaBright,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 40),

          // Brand name + taglines
          AnimatedBuilder(
            animation: _nameFadeAnimation,
            builder: (context, child) =>
                Opacity(opacity: _nameFadeAnimation.value, child: child),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [PalmColors.aquaBright, Colors.white, PalmColors.aquaBright],
                  ).createShader(bounds),
                  child: const Text(
                    'PALMNAZI',
                    style: TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 6,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'RESORT CITIES',
                  style: TextStyle(
                    fontSize: 20,
                    letterSpacing: 10,
                    fontWeight: FontWeight.w300,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 30),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: const Text(
                    "Discover Kenya's Most Exquisite Resort Destinations",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w400,
                      color: PalmColors.aquaBright,
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Main scrollable content ──────────────────────────────────────────────
  // CHANGE 3: _buildCallToAction() call removed from slivers

  Widget _buildMainContent() {
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: kToolbarHeight + 10)),

        // Hero heading
        SliverToBoxAdapter(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
                child: Column(
                  children: [
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [Colors.white, PalmColors.aquaBright],
                      ).createShader(bounds),
                      child: Text(
                        'Choose Your Destination',
                        style: Theme.of(context).textTheme.displayMedium?.copyWith(
                          fontSize: 42,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Select a resort city to explore its unique channels and experiences',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontSize: 16,
                        color: Colors.white.withValues(alpha: 0.88),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // CHANGE 2: Search form inserted directly after the heading
        SliverToBoxAdapter(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: _buildSearchForm(),
          ),
        ),

        // City cards grid
        SliverToBoxAdapter(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: _buildResortCitiesGrid(),
          ),
        ),

        // Stats — CHANGE 7: StatsCounter itself uses horizontal layout
        // (see stats_counter.dart — children wrapped in Row/Flexible)
        SliverToBoxAdapter(
          child: FadeTransition(opacity: _fadeAnimation, child: const StatsCounter()),
        ),

        // CHANGE 3: _buildCallToAction() removed — no CTA section here

        SliverToBoxAdapter(child: _buildFooter()),
      ],
    );
  }

  // ── CHANGE 2: Search form widget ─────────────────────────────────────────

  Widget _buildSearchForm() {
    final isMobile = MediaQuery.of(context).size.width < 700;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF00838F), // vivid teal
              Color(0xFF006978), // slightly deeper teal
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: PalmColors.aquaBright.withValues(alpha: 0.55),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00838F).withValues(alpha: 0.55),
              blurRadius: 32,
              spreadRadius: 4,
            ),
          ],
        ),
        child: isMobile
            ? _buildSearchFormMobile()
            : _buildSearchFormDesktop(),
      ),
    );
  }

  // Desktop: all fields in one Row
  Widget _buildSearchFormDesktop() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Place / Channel search
        Expanded(
          flex: 3,
          child: _buildSearchField(),
        ),
        const SizedBox(width: 12),

        // Check-in
        Expanded(
          flex: 2,
          child: _buildDateField(
            label: 'Check-in',
            date: _checkInDate,
            onTap: () => _pickDate(isCheckIn: true),
          ),
        ),
        const SizedBox(width: 12),

        // Check-out
        Expanded(
          flex: 2,
          child: _buildDateField(
            label: 'Check-out',
            date: _checkOutDate,
            onTap: () => _pickDate(isCheckIn: false),
          ),
        ),
        const SizedBox(width: 12),

        // Guest counter
        Expanded(
          flex: 2,
          child: _buildGuestField(),
        ),
        const SizedBox(width: 16),

        // Search button
        _buildSearchButton(),
      ],
    );
  }

  // Mobile: stacked in Column, full-width
  Widget _buildSearchFormMobile() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSearchField(),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildDateField(
                label: 'Check-in',
                date: _checkInDate,
                onTap: () => _pickDate(isCheckIn: true),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildDateField(
                label: 'Check-out',
                date: _checkOutDate,
                onTap: () => _pickDate(isCheckIn: false),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildGuestField(),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: _buildSearchButton()),
      ],
    );
  }

  // ── Search field: place / channel ────────────────────────────────────────
  Widget _buildSearchField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Place / Channel',
          style: TextStyle(
            color: PalmColors.aquaBright,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _searchController,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Search destinations or channels…',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 13),
            prefixIcon: const Icon(Icons.search, color: PalmColors.aquaBright, size: 20),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.20),
            contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.20)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.20)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: PalmColors.aquaBright, width: 1.5),
            ),
          ),
          onSubmitted: (_) => _handleSearch(),
        ),
      ],
    );
  }

  // ── Date field ────────────────────────────────────────────────────────────
  Widget _buildDateField({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
  }) {
    final String display = date == null
        ? 'Select date'
        : '${date.day}/${date.month}/${date.year}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: PalmColors.aquaBright,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.45)),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_outlined,
                    color: PalmColors.aquaBright, size: 16),
                const SizedBox(width: 8),
                Text(
                  display,
                  style: TextStyle(
                    color: date == null
                        ? Colors.white.withValues(alpha: 0.45)
                        : Colors.white,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Guest counter field ───────────────────────────────────────────────────
  Widget _buildGuestField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Guests',
          style: TextStyle(
            color: PalmColors.aquaBright,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.20),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.45)),
          ),
          // Stack adults and children vertically — works at any column width
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildGuestCounter(
                label: 'Adults',
                count: _adultCount,
                onDecrement: () {
                  if (_adultCount > 1) setState(() => _adultCount--);
                },
                onIncrement: () => setState(() => _adultCount++),
              ),
              const SizedBox(height: 8),
              _buildGuestCounter(
                label: 'Children',
                count: _childCount,
                onDecrement: () {
                  if (_childCount > 0) setState(() => _childCount--);
                },
                onIncrement: () => setState(() => _childCount++),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGuestCounter({
    required String label,
    required int count,
    required VoidCallback onDecrement,
    required VoidCallback onIncrement,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.max,   // fill available width
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.70), fontSize: 12),
        ),
        GestureDetector(
          onTap: onDecrement,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.15),
            ),
            child: const Icon(Icons.remove, color: Colors.white, size: 14),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            '$count',
            style: const TextStyle(
                color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
        GestureDetector(
          onTap: onIncrement,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: PalmColors.aquaBright.withValues(alpha: 0.25),
            ),
            child: const Icon(Icons.add, color: PalmColors.aquaBright, size: 14),
          ),
        ),
      ],
    );
  }

  // ── Search button ─────────────────────────────────────────────────────────
  Widget _buildSearchButton() {
    return ElevatedButton.icon(
      onPressed: _handleSearch,
      icon: const Icon(Icons.search, size: 18),
      label: const Text(
        'Search',
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: PalmColors.aquaBright,
        foregroundColor: PalmColors.deepNavy,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 4,
        shadowColor: PalmColors.aqua.withValues(alpha: 0.50),
      ),
    );
  }

  // ── Resort cities grid ───────────────────────────────────────────────────
  // CHANGE 6: Mobile → horizontal ListView cards; tablet/desktop → grid

  Widget _buildResortCitiesGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 700;

          if (isMobile) {
            // ── Mobile: horizontal scrolling list of slim cards ────────────
            return SizedBox(
              height: 130,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _resortCities.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (context, index) =>
                    _buildMobileCityCard(_resortCities[index]),
              ),
            );
          }

          // ── Tablet / Desktop: original grid ───────────────────────────────
          final crossAxisCount = constraints.maxWidth > 1200 ? 3 : 2;
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: 0.85,
              crossAxisSpacing: 24,
              mainAxisSpacing: 24,
            ),
            itemCount: _resortCities.length,
            itemBuilder: (context, index) =>
                _buildResortCityCard(_resortCities[index]),
          );
        },
      ),
    );
  }

  // ── CHANGE 6: Mobile city card — horizontal, 80% image, minimal text ─────
  Widget _buildMobileCityCard(ResortCityItem city) {
    return GestureDetector(
      onTap: () => _navigateToCity(city),
      child: Container(
        width: 260,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: city.color.withValues(alpha: 0.40),
              blurRadius: 16,
              spreadRadius: 1,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              // Image — fills the full card (80%+ visual weight)
              Positioned.fill(
                child: RobustAssetImage(
                  imagePath: city.assetPath,
                  fit: BoxFit.cover,
                  fallbackColor: city.color,
                  fallbackIcon: Icons.location_city,
                ),
              ),

              // Bottom gradient scrim — slim, just enough for text
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.78),
                      ],
                    ),
                  ),
                ),
              ),

              // Text + CTA — right-aligned slim column
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 110,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // City name
                      Text(
                        city.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),

                      // 3–4 word short description
                      Text(
                        _shortTagline(city.tagline),
                        style: TextStyle(
                          fontSize: 11,
                          color: city.color,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),

                      // Compact CTA
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: PalmColors.aquaBright,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Explore',
                          style: TextStyle(
                            color: PalmColors.deepNavy,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
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

  /// Trims a tagline to at most 4 words for the mobile card
  String _shortTagline(String tagline) {
    final words = tagline.split(' ');
    return words.length <= 4 ? tagline : '${words.take(4).join(' ')}…';
  }

  // ── Desktop / tablet city card (unchanged layout) ─────────────────────────
  Widget _buildResortCityCard(ResortCityItem city) {
    return GestureDetector(
      onTap: () => _navigateToCity(city),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: city.color.withValues(alpha: 0.45),
              blurRadius: 24,
              spreadRadius: 2,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              Positioned.fill(
                child: RobustAssetImage(
                  imagePath: city.assetPath,
                  fit: BoxFit.cover,
                  fallbackColor: city.color,
                  fallbackIcon: Icons.location_city,
                ),
              ),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.08),
                        Colors.black.withValues(alpha: 0.70),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        city.name,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        city.tagline,
                        style: TextStyle(
                          fontSize: 16,
                          color: city.color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        city.description,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.90),
                          height: 1.4,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: city.highlights.take(3).map((highlight) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: city.color.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: city.color.withValues(alpha: 0.65),
                                width: 1.2,
                              ),
                            ),
                            child: Text(
                              highlight,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          color: PalmColors.aquaBright,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: PalmColors.aqua.withValues(alpha: 0.55),
                              blurRadius: 16,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Explore City',
                              style: TextStyle(
                                color: PalmColors.deepNavy,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(Icons.arrow_forward,
                                color: PalmColors.deepNavy, size: 16),
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

  // ── Footer ───────────────────────────────────────────────────────────────
  // CHANGE 8: Nav links use Wrap so they always centre-wrap on mobile

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(48),
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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Wrap centres links and wraps gracefully on narrow screens
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              _buildFooterLink('About'),
              _buildFooterLink('Contact'),
              _buildFooterLink('Privacy'),
              _buildFooterLink('Terms'),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            '© 2026 Palmnazi Resort Cities. All rights reserved.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.60),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterLink(String text) {
    return TextButton(
      onPressed: () {},
      child: Text(
        text,
        style: const TextStyle(
          color: PalmColors.aquaBright,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}