import 'package:flutter/material.dart';
import 'package:palmnazi/screens/auth_screen.dart';
import 'package:palmnazi/screens/resort_city_screen.dart';
import 'package:palmnazi/widgets/animated_background.dart';
import 'package:palmnazi/widgets/stats_counter.dart';
import 'package:palmnazi/models/models.dart';
import 'dart:async';

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
  late AnimationController _textController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _logoScaleAnimation;
  late Animation<Offset> _logoSlideAnimation;
  late Animation<double> _textFadeAnimation;
  
  double _scrollOffset = 0;
  bool _showMainContent = false;

  // Resort Cities Data - This will come from backend
  final List<ResortCityItem> _resortCities = [
    ResortCityItem(
      id: '1',
      name: 'Mombasa',
      tagline: 'The Coastal Paradise',
      description: 'Experience pristine beaches, rich Swahili culture, and world-class resorts along the Indian Ocean coastline.',
      imagePath: 'images/cities/mombasa.jpg',
      color: const Color(0xFF0D7377),
      highlights: ['Pristine Beaches', 'Water Sports', 'Cultural Heritage', 'Luxury Resorts'],
    ),
    ResortCityItem(
      id: '2',
      name: 'Malindi',
      tagline: 'Where History Meets the Sea',
      description: 'Discover ancient ruins, marine parks, and serene coastal beauty in this historic coastal town.',
      imagePath: 'images/cities/malindi.jpg',
      color: const Color(0xFF2196F3),
      highlights: ['Marine Parks', 'Historic Sites', 'Beach Resorts', 'Water Activities'],
    ),
    ResortCityItem(
      id: '3',
      name: 'Diani Beach',
      tagline: 'Tropical Heaven on Earth',
      description: 'Indulge in powder-white sand beaches, crystal-clear waters, and luxury beachfront accommodations.',
      imagePath: 'images/cities/diani.jpg',
      color: const Color(0xFF00897B),
      highlights: ['White Sand Beaches', 'Diving & Snorkeling', 'Luxury Villas', 'Nightlife'],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()
      ..addListener(_onScroll);
    
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _logoController = AnimationController(
      duration: const Duration(milliseconds: 4000),
      vsync: this,
    );

    _textController = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
    );

    _logoScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.5, end: 1.1).chain(
          CurveTween(curve: Curves.easeOut),
        ),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.1, end: 0.6).chain(
          CurveTween(curve: Curves.easeInOut),
        ),
        weight: 60,
      ),
    ]).animate(_logoController);

    _logoSlideAnimation = TweenSequence<Offset>([
      TweenSequenceItem(
        tween: Tween<Offset>(
          begin: Offset.zero,
          end: Offset.zero,
        ),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<Offset>(
          begin: Offset.zero,
          end: const Offset(0, -2.5),
        ).chain(
          CurveTween(curve: Curves.easeInOut),
        ),
        weight: 50,
      ),
    ]).animate(_logoController);

    _textFadeAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0).chain(
          CurveTween(curve: Curves.easeIn),
        ),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(1.0),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.0).chain(
          CurveTween(curve: Curves.easeOut),
        ),
        weight: 25,
      ),
    ]).animate(_textController);
    
    _startIntroAnimation();
  }

  void _startIntroAnimation() async {
    _logoController.forward();
    
    await Future.delayed(const Duration(milliseconds: 1000));
    _textController.forward();
    
    await Future.delayed(const Duration(milliseconds: 5000));
    
    if (mounted) {
      setState(() {
        _showMainContent = true;
      });
      _fadeController.forward();
      _slideController.forward();
      
      Timer(const Duration(milliseconds: 800), _scrollToCities);
    }
  }

  void _scrollToCities() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        10.0,
        duration: const Duration(milliseconds: 1200),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _onScroll() {
    setState(() {
      _scrollOffset = _scrollController.offset;
    });
  }

  void _navigateToCity(ResortCityItem city) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ResortCityScreen(city: city),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    _logoController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const AnimatedBackground(),
          
          if (!_showMainContent)
            _buildIntroScreen()
          else
            _buildMainContent(),
          
          if (_showMainContent)
            _buildAppBar(),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    final opacity = (_scrollOffset / 100).clamp(0.0, 1.0);
    
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.7 * opacity),
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
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF14FFEC), Color(0xFF0D7377)],
                        ),
                      ),
                      child: const Icon(
                        Icons.landscape,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'PALMNAZI',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.95),
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const AuthScreen(isLogin: true),
                          ),
                        );
                      },
                      child: const Text(
                        'Sign In',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const AuthScreen(isLogin: false),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF14FFEC),
                        foregroundColor: const Color(0xFF1E3A5F),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: const Text(
                        'Get Started',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
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

  Widget _buildIntroScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: Listenable.merge([_logoScaleAnimation, _logoSlideAnimation]),
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(
                  0,
                  _logoSlideAnimation.value.dy * MediaQuery.of(context).size.height,
                ),
                child: Transform.scale(
                  scale: _logoScaleAnimation.value,
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF14FFEC),
                          Color(0xFF0D7377),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF14FFEC).withValues(alpha: 0.6),
                          blurRadius: 50,
                          spreadRadius: 15,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Image.asset(
                        'images/logo.png',
                        width: 90,
                        height: 90,
                        errorBuilder: (context, error, stackTrace) {
                          return const Icon(
                            Icons.landscape,
                            size: 70,
                            color: Colors.white,
                          );
                        },
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 40),
          
          Opacity(
            opacity: _textFadeAnimation.value,
            child: ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Color(0xFF14FFEC), Colors.white, Color(0xFF14FFEC)],
              ).createShader(bounds),
              child: const Text(
                'PALMNAZI',
                style: TextStyle(
                  fontSize: 64,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 6,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          
          Opacity(
            opacity: _textFadeAnimation.value,
            child: const Text(
              'RESORT CITIES',
              style: TextStyle(
                fontSize: 20,
                letterSpacing: 10,
                fontWeight: FontWeight.w300,
                color: Colors.white70,
              ),
            ),
          ),
          const SizedBox(height: 30),
          
          Opacity(
            opacity: _textFadeAnimation.value,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Text(
                'Discover Kenya\'s Most Exquisite Resort Destinations',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w400,
                  color: const Color(0xFF14FFEC).withValues(alpha: 0.9),
                  letterSpacing: 0.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(height: kToolbarHeight + 10),
        ),
        
        // Resort Cities Section Header
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
                        colors: [Color(0xFF14FFEC), Colors.white],
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
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        
        // Resort Cities Grid
        SliverToBoxAdapter(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: _buildResortCitiesGrid(),
          ),
        ),
        
        // Stats Counter
        SliverToBoxAdapter(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: const StatsCounter(),
          ),
        ),

        // Call to Action Section
        SliverToBoxAdapter(
          child: _buildCallToAction(),
        ),
        
        // Footer
        SliverToBoxAdapter(
          child: _buildFooter(),
        ),
      ],
    );
  }

  Widget _buildResortCitiesGrid() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isLargeScreen = constraints.maxWidth > 1200;
          final isMediumScreen = constraints.maxWidth > 800;
          
          final crossAxisCount = isLargeScreen ? 3 : (isMediumScreen ? 2 : 1);
          
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
            itemBuilder: (context, index) {
              return _buildResortCityCard(_resortCities[index]);
            },
          );
        },
      ),
    );
  }

  Widget _buildResortCityCard(ResortCityItem city) {
    return GestureDetector(
      onTap: () => _navigateToCity(city),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: city.color.withValues(alpha: 0.4),
              blurRadius: 20,
              spreadRadius: 2,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              // Background Image
              Positioned.fill(
                child: Image.asset(
                  city.imagePath,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            city.color,
                            city.color.withValues(alpha: 0.7),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              
              // Gradient Overlay
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.2),
                        Colors.black.withValues(alpha: 0.8),
                      ],
                    ),
                  ),
                ),
              ),
              
              // Content
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // City Name
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
                      
                      // Tagline
                      Text(
                        city.tagline,
                        style: TextStyle(
                          fontSize: 16,
                          color: const Color(0xFF14FFEC).withValues(alpha: 0.9),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      // Description
                      Text(
                        city.description,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.85),
                          height: 1.4,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 16),
                      
                      // Highlights
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: city.highlights.take(3).map((highlight) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              highlight,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      
                      // Explore Button
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF14FFEC),
                              city.color,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF14FFEC).withValues(alpha: 0.5),
                              blurRadius: 15,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Explore City',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.arrow_forward,
                              color: Colors.white,
                              size: 16,
                            ),
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

  Widget _buildCallToAction() {
    return Container(
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0D7377),
            Color(0xFF1E3A5F),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0D7377).withValues(alpha: 0.4),
            blurRadius: 30,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            'Ready to Explore Paradise?',
            style: Theme.of(context).textTheme.displayMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'Join thousands of travelers discovering the most beautiful resort cities in Kenya.',
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AuthScreen(isLogin: false),
                    ),
                  );
                },
                icon: const Icon(Icons.person_add),
                label: const Text('Get Started'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF14FFEC),
                  foregroundColor: const Color(0xFF1E3A5F),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 48,
                    vertical: 20,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.7),
          ],
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildFooterLink('About'),
              const SizedBox(width: 24),
              _buildFooterLink('Contact'),
              const SizedBox(width: 24),
              _buildFooterLink('Privacy'),
              const SizedBox(width: 24),
              _buildFooterLink('Terms'),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            '© 2026 Palmnazi Resort Cities. All rights reserved.',
            style: Theme.of(context).textTheme.bodyMedium,
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
          color: Colors.white70,
          fontSize: 14,
        ),
      ),
    );
  }
}