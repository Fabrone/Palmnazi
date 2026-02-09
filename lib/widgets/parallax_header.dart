import 'package:flutter/material.dart';

class ParallaxHeader extends StatefulWidget {
  final double scrollOffset;
  final VoidCallback onExplore;

  const ParallaxHeader({
    super.key,
    required this.scrollOffset,
    required this.onExplore,
  });

  @override
  State<ParallaxHeader> createState() => _ParallaxHeaderState();
}

class _ParallaxHeaderState extends State<ParallaxHeader>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _floatController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _floatAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _floatController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _floatAnimation = Tween<double>(begin: -10.0, end: 10.0).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _floatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final parallaxOffset = widget.scrollOffset * 0.4;
    final opacity = (1 - (widget.scrollOffset / screenHeight)).clamp(0.0, 1.0);

    return SizedBox(
      height: screenHeight * 0.85,
      child: Stack(
        children: [
          // Gradient Background with parallax
          Positioned.fill(
            child: Transform.translate(
              offset: Offset(0, -parallaxOffset),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF1E3A5F).withValues(alpha: 0.6),
                      const Color(0xFF0D7377).withValues(alpha: 0.8),
                      const Color(0xFF0A1128).withValues(alpha: 0.9),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Animated circles background
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _floatController,
              builder: (context, child) {
                return CustomPaint(
                  painter: CirclesPainter(animationValue: _floatController.value),
                );
              },
            ),
          ),

          // Content
          Positioned.fill(
            child: SafeArea(
              child: Opacity(
                opacity: opacity,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(),
                    
                    // Logo with float animation
                    AnimatedBuilder(
                      animation: Listenable.merge([_pulseAnimation, _floatAnimation]),
                      builder: (context, child) {
                        return Transform.translate(
                          offset: Offset(0, _floatAnimation.value),
                          child: Transform.scale(
                            scale: _pulseAnimation.value,
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
                                  'assets/images/logo.png',
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
                    
                    const SizedBox(height: 50),
                    
                    // Main Title with shimmer effect
                    TweenAnimationBuilder<double>(
                      duration: const Duration(milliseconds: 1500),
                      tween: Tween(begin: 0.0, end: 1.0),
                      builder: (context, value, child) {
                        return Opacity(
                          opacity: value,
                          child: Transform.translate(
                            offset: Offset(0, 50 * (1 - value)),
                            child: child,
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          children: [
                            ShaderMask(
                              shaderCallback: (bounds) => LinearGradient(
                                colors: const [
                                  Color(0xFF14FFEC),
                                  Colors.white,
                                  Color(0xFF14FFEC),
                                ],
                                stops: [
                                  (_pulseController.value - 0.3).clamp(0.0, 1.0),
                                  _pulseController.value,
                                  (_pulseController.value + 0.3).clamp(0.0, 1.0),
                                ],
                              ).createShader(bounds),
                              child: Text(
                                'PALMNAZI',
                                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                                  fontSize: 64,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 6,
                                  color: Colors.white,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'RESORT CITIES',
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                letterSpacing: 10,
                                fontWeight: FontWeight.w300,
                                color: Colors.white70,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 30),
                    
                    // Tagline with typewriter effect
                    TweenAnimationBuilder<double>(
                      duration: const Duration(milliseconds: 2000),
                      tween: Tween(begin: 0.0, end: 1.0),
                      builder: (context, value, child) {
                        return Opacity(
                          opacity: value,
                          child: child,
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 48),
                        child: Text(
                          'Discover Kenya\'s Most Exquisite Resort Destinations',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontSize: 20,
                            fontWeight: FontWeight.w400,
                            color: const Color(0xFF14FFEC),
                            letterSpacing: 0.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 50),
                    
                    // CTA Button with glow
                    TweenAnimationBuilder<double>(
                      duration: const Duration(milliseconds: 2500),
                      tween: Tween(begin: 0.0, end: 1.0),
                      builder: (context, value, child) {
                        return Opacity(
                          opacity: value,
                          child: Transform.scale(
                            scale: value,
                            child: child,
                          ),
                        );
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(50),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF14FFEC).withValues(alpha: 0.5),
                              blurRadius: 30,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: ElevatedButton.icon(
                          onPressed: widget.onExplore,
                          icon: const Icon(Icons.explore, size: 28),
                          label: const Text(
                            'Explore Destinations',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF14FFEC),
                            foregroundColor: const Color(0xFF1E3A5F),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 48,
                              vertical: 24,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(50),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ),
                    
                    const Spacer(),
                    
                    // Scroll Indicator with animation
                    AnimatedBuilder(
                      animation: _floatController,
                      builder: (context, child) {
                        return Opacity(
                          opacity: (1 - (widget.scrollOffset / 200)).clamp(0.0, 1.0),
                          child: Transform.translate(
                            offset: Offset(0, _floatAnimation.value * 0.5),
                            child: Column(
                              children: [
                                Text(
                                  'Scroll to discover more',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontSize: 12,
                                    letterSpacing: 2,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Icon(
                                  Icons.keyboard_arrow_down,
                                  color: const Color(0xFF14FFEC).withValues(alpha: 0.8),
                                  size: 32,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Custom painter for animated circles
class CirclesPainter extends CustomPainter {
  final double animationValue;

  CirclesPainter({required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Draw multiple circles with different sizes and positions
    for (int i = 0; i < 5; i++) {
      final radius = (size.width / 4) + (i * 50) + (animationValue * 20);
      paint.color = const Color(0xFF14FFEC).withValues(alpha: 0.05 - (i * 0.01));
      
      canvas.drawCircle(
        Offset(size.width * 0.3, size.height * 0.4),
        radius,
        paint,
      );
      
      canvas.drawCircle(
        Offset(size.width * 0.7, size.height * 0.6),
        radius * 0.8,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CirclesPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}