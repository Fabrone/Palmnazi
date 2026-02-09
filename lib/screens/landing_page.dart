import 'package:flutter/material.dart';
import 'package:palmnazi/screens/auth_screen.dart';
import 'package:palmnazi/widgets/animated_background.dart';
import 'package:palmnazi/widgets/channel_showcase.dart';
import 'package:palmnazi/widgets/feature_carousel.dart';
import 'package:palmnazi/widgets/parallax_header.dart';
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
  late AnimationController _introController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  
  double _scrollOffset = 0;
  bool _showMainContent = false;
  bool _autoScrolledToCarousel = false;

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

    _introController = AnimationController(
      duration: const Duration(milliseconds: 3000),
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
    
    // Start intro animation
    _introController.forward();
    
    // After 4 seconds, show main content and scroll to carousel
    Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _showMainContent = true;
        });
        _fadeController.forward();
        _slideController.forward();
        
        // Auto-scroll to carousel after another 1 second
        Timer(const Duration(milliseconds: 1000), _scrollToCarousel);
      }
    });
  }

  void _scrollToCarousel() {
    if (_scrollController.hasClients && !_autoScrolledToCarousel) {
      setState(() {
        _autoScrolledToCarousel = true;
      });
      _scrollController.animateTo(
        MediaQuery.of(context).size.height * 0.85, // Scroll to carousel
        duration: const Duration(milliseconds: 1500),
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
    _introController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: _showMainContent ? _buildAppBar() : null,
      body: Stack(
        children: [
          // Animated Background
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
    return AppBar(
      backgroundColor: Colors.black.withValues(alpha: 0.3),
      elevation: 0,
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFF14FFEC), Color(0xFF0D7377)],
              ),
            ),
            child: const Icon(Icons.landscape, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          const Text(
            'PALMNAZI',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 20,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => _scrollToSection(0),
          child: const Text('Home', style: TextStyle(color: Colors.white)),
        ),
        PopupMenuButton<String>(
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text('Channels', style: TextStyle(color: Colors.white)),
                SizedBox(width: 4),
                Icon(Icons.arrow_drop_down, color: Colors.white),
              ],
            ),
          ),
          onSelected: (value) => _handleInteraction('explore $value'),
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'Hotels', child: Text('Hotels')),
            const PopupMenuItem(value: 'Restaurants', child: Text('Restaurants')),
            const PopupMenuItem(value: 'Events', child: Text('Events')),
            const PopupMenuItem(value: 'Shopping', child: Text('Shopping')),
            const PopupMenuItem(value: 'Wellness', child: Text('Wellness')),
            const PopupMenuItem(value: 'Activities', child: Text('Activities')),
            const PopupMenuItem(value: 'Nightlife', child: Text('Nightlife')),
            const PopupMenuItem(value: 'Beaches', child: Text('Beaches')),
          ],
        ),
        TextButton(
          onPressed: () => _handleInteraction('view about us'),
          child: const Text('About', style: TextStyle(color: Colors.white)),
        ),
        TextButton(
          onPressed: () => _handleInteraction('contact us'),
          child: const Text('Contact', style: TextStyle(color: Colors.white)),
        ),
        const SizedBox(width: 8),
        // Auth Dropdown
        PopupMenuButton<String>(
          icon: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF14FFEC), Color(0xFF0D7377)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              children: [
                Icon(Icons.person, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Sign In', style: TextStyle(color: Colors.white)),
                SizedBox(width: 4),
                Icon(Icons.arrow_drop_down, color: Colors.white, size: 20),
              ],
            ),
          ),
          onSelected: (value) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AuthScreen(isLogin: value == 'login'),
              ),
            );
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'login',
              child: Row(
                children: [
                  Icon(Icons.login),
                  SizedBox(width: 12),
                  Text('Login'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'signup',
              child: Row(
                children: [
                  Icon(Icons.person_add),
                  SizedBox(width: 12),
                  Text('Sign Up'),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(width: 16),
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
        offset = MediaQuery.of(context).size.height * 0.85;
        break;
      case 2:
        offset = MediaQuery.of(context).size.height * 1.5;
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
        animation: _introController,
        builder: (context, child) {
          return Opacity(
            opacity: _introController.value < 0.8 ? _introController.value * 1.25 : 1.0,
            child: Transform.scale(
              scale: 0.8 + (_introController.value * 0.2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
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
                    child: const Icon(
                      Icons.landscape,
                      size: 80,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 40),
                  ShaderMask(
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
                  const SizedBox(height: 12),
                  const Text(
                    'RESORT CITIES',
                    style: TextStyle(
                      fontSize: 20,
                      letterSpacing: 10,
                      fontWeight: FontWeight.w300,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: 30,
                    height: 30,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.white.withValues(alpha: 0.7),
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
        // Parallax Header
        SliverToBoxAdapter(
          child: ParallaxHeader(
            scrollOffset: _scrollOffset,
            onExplore: () => _scrollToSection(1),
          ),
        ),
        
        // Feature Carousel
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
            'Ready to Explore Resort Cities?',
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