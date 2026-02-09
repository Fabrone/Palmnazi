import 'package:flutter/material.dart';
import 'package:palmnazi/screens/auth_screen.dart';
import 'package:palmnazi/widgets/animated_background.dart';
import 'package:palmnazi/widgets/channel_showcase.dart';
import 'package:palmnazi/widgets/feature_carousel.dart';
import 'package:palmnazi/widgets/stats_counter.dart';
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
      duration: const Duration(milliseconds: 4000), // Extended to 4 seconds
      vsync: this,
    );

    _textController = AnimationController(
      duration: const Duration(milliseconds: 2500), // Extended to 2.5 seconds
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
    
    // Start intro animation sequence
    _startIntroAnimation();
  }

  void _startIntroAnimation() async {
    // Start logo animation
    _logoController.forward();
    
    // Start text animation with delay
    await Future.delayed(const Duration(milliseconds: 1000));
    _textController.forward();
    
    // Wait for animations to complete (longer display time)
    await Future.delayed(const Duration(milliseconds: 5000));
    
    if (mounted) {
      setState(() {
        _showMainContent = true;
      });
      _fadeController.forward();
      _slideController.forward();
      
      // Auto-scroll to carousel with proper offset
      Timer(const Duration(milliseconds: 800), _scrollToCarousel);
    }
  }

  void _scrollToCarousel() {
    if (_scrollController.hasClients) {
      // Scroll to show "What We Offer" title properly below appbar
      _scrollController.animateTo(
        10.0, // Minimal scroll to position title just below appbar
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

  void _handleInteraction(String action) {
    _showAuthDialog(action);
  }

  void _showAuthDialog(String action) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF1E3A5F),
                Color(0xFF0D7377),
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
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.lock_outline,
                  size: 64,
                  color: Colors.white,
                ),
                const SizedBox(height: 24),
                Text(
                  'Sign In Required',
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'To $action, please sign in or create an account to unlock the full Palmnazi experience.',
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const AuthScreen(isLogin: false),
                            ),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white, width: 2),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: const Text('Sign Up'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const AuthScreen(isLogin: true),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF14FFEC),
                          foregroundColor: const Color(0xFF1E3A5F),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: const Text('Sign In'),
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
      extendBodyBehindAppBar: true,
      appBar: _showMainContent ? _buildAppBar() : null,
      body: Stack(
        children: [
          // Animated Background (always visible)
          const AnimatedBackground(),
          
          // Intro Animation or Main Content
          if (!_showMainContent)
            _buildIntroAnimation()
          else
            _buildMainContent(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final appBarOpacity = (_scrollOffset / 100).clamp(0.0, 1.0);
    
    return AppBar(
      backgroundColor: Color.lerp(
        Colors.black.withValues(alpha: 0.3),
        Colors.black.withValues(alpha: 0.9),
        appBarOpacity,
      ),
      elevation: appBarOpacity * 8,
      title: Row(
        children: [
          // Logo
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF14FFEC), Color(0xFF0D7377)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF14FFEC).withValues(alpha: 0.4),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Center(
              child: ClipOval(
                child: Image.asset(
                  'assets/images/logo.png',
                  width: 28,
                  height: 28,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return const Icon(
                      Icons.landscape,
                      size: 24,
                      color: Colors.white,
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'PALMNAZI',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
              color: Colors.white,
            ),
          ),
        ],
      ),
      actions: [
        // Navigation buttons
        TextButton.icon(
          onPressed: () => _scrollToSection(0),
          icon: const Icon(Icons.home_outlined, color: Colors.white, size: 20),
          label: const Text(
            'Home',
            style: TextStyle(color: Colors.white),
          ),
        ),
        TextButton.icon(
          onPressed: () => _scrollToSection(1),
          icon: const Icon(Icons.explore_outlined, color: Colors.white, size: 20),
          label: const Text(
            'Explore',
            style: TextStyle(color: Colors.white),
          ),
        ),
        // Channels Dropdown
        PopupMenuButton<String>(
          icon: const Icon(Icons.apps, color: Colors.white),
          tooltip: 'Channels',
          onSelected: (String channel) => _handleInteraction('explore $channel'),
          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
            const PopupMenuItem<String>(
              value: 'Accommodation',
              child: ListTile(
                leading: Icon(Icons.king_bed_outlined, color: Color(0xFF0D7377)),
                title: Text('Accommodation'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem<String>(
              value: 'Dining',
              child: ListTile(
                leading: Icon(Icons.restaurant_menu, color: Color(0xFFE91E63)),
                title: Text('Dining'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem<String>(
              value: 'Events',
              child: ListTile(
                leading: Icon(Icons.celebration, color: Color(0xFFFF9800)),
                title: Text('Events'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem<String>(
              value: 'Shopping',
              child: ListTile(
                leading: Icon(Icons.shopping_bag_outlined, color: Color(0xFF9C27B0)),
                title: Text('Shopping'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem<String>(
              value: 'Adventure',
              child: ListTile(
                leading: Icon(Icons.terrain, color: Color(0xFF2196F3)),
                title: Text('Adventure'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem<String>(
              value: 'Wellness',
              child: ListTile(
                leading: Icon(Icons.spa_outlined, color: Color(0xFF00897B)),
                title: Text('Wellness'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
        // Auth buttons
        Padding(
          padding: const EdgeInsets.only(left: 8, right: 8),
          child: OutlinedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AuthScreen(isLogin: true),
                ),
              );
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white, width: 1.5),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25),
              ),
            ),
            child: const Text('Sign In'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: ElevatedButton(
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25),
              ),
              elevation: 4,
            ),
            child: const Text(
              'Get Started',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  void _scrollToSection(int section) {
    double offset = 0;
    switch (section) {
      case 0:
        offset = 0;
        break;
      case 1:
        offset = 10.0;
        break;
    }
    
    _scrollController.animateTo(
      offset,
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOutCubic,
    );
  }

  Widget _buildIntroAnimation() {
    return Center(
      child: AnimatedBuilder(
        animation: Listenable.merge([_logoController, _textController]),
        builder: (context, child) {
          return Transform.scale(
            scale: _logoScaleAnimation.value,
            child: Transform.translate(
              offset: Offset(
                0,
                _logoSlideAnimation.value.dy * MediaQuery.of(context).size.height,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo
                  Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF14FFEC), Color(0xFF0D7377)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF14FFEC).withValues(alpha: 0.6),
                          blurRadius: 60,
                          spreadRadius: 20,
                        ),
                      ],
                    ),
                    child: Center(
                      child: ClipOval(
                        child: Image.asset(
                          'assets/images/logo.png',
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(
                              Icons.landscape,
                              size: 80,
                              color: Colors.white,
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  
                  // App Name
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
                  
                  // Subtitle
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
                  
                  // Tagline
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
            ),
          );
        },
      ),
    );
  }

  Widget _buildMainContent() {
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        // Small header spacer - adjusted for appbar clearance
        SliverToBoxAdapter(
          child: SizedBox(height: kToolbarHeight + 10),
        ),
        
        // Feature Carousel (What We Offer)
        SliverToBoxAdapter(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: FeatureCarousel(
                onFeatureTap: (feature) => _handleInteraction('access $feature'),
              ),
            ),
          ),
        ),
        
        // Channel Showcase
        SliverToBoxAdapter(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: ChannelShowcase(
              onChannelTap: (channel) => _handleInteraction('explore $channel'),
            ),
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
            'Join thousands of travelers discovering the most beautiful resort cities in Kenya and beyond.',
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
      onPressed: () => _handleInteraction('view $text'),
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