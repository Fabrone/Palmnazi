import 'package:flutter/material.dart';
import 'dart:math' as math;

class AnimatedBackground extends StatefulWidget {
  const AnimatedBackground({super.key});

  @override
  State<AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<AnimatedBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<Particle> _particles = [];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    )..repeat();

    // Initialize particles for floating effect
    for (int i = 0; i < 40; i++) {
      _particles.add(Particle());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Hero Background Image
        Positioned.fill(
          child: Image.asset(
            'assets/images/hero_background.png',
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              // Fallback gradient if image not found
              return Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF0A1128), // Deep navy
                      Color(0xFF1E3A5F), // Medium blue
                      Color(0xFF0D7377), // Teal
                      Color(0xFF0A1128), // Back to deep navy
                    ],
                    stops: [0.0, 0.35, 0.7, 1.0],
                  ),
                ),
              );
            },
          ),
        ),
        
        // Opaque overlay for better content visibility
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.55),
                  Colors.black.withValues(alpha: 0.65),
                  Colors.black.withValues(alpha: 0.55),
                ],
              ),
            ),
          ),
        ),
        
        // Animated gradient overlay with subtle movement
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(
                    math.cos(_controller.value * 2 * math.pi),
                    math.sin(_controller.value * 2 * math.pi),
                  ),
                  end: Alignment(
                    -math.cos(_controller.value * 2 * math.pi),
                    -math.sin(_controller.value * 2 * math.pi),
                  ),
                  colors: [
                    const Color(0xFF14FFEC).withValues(alpha: 0.06),
                    const Color(0xFF0D7377).withValues(alpha: 0.08),
                    const Color(0xFF14FFEC).withValues(alpha: 0.06),
                  ],
                ),
              ),
            );
          },
        ),
        
        // Floating particles (bubbles)
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return CustomPaint(
              painter: ParticlePainter(
                particles: _particles,
                animationValue: _controller.value,
              ),
              size: Size.infinite,
            );
          },
        ),
        
        // Animated circles (larger bubbles)
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return CustomPaint(
              painter: AnimatedCirclesPainter(animationValue: _controller.value),
              size: Size.infinite,
            );
          },
        ),
        
        // Subtle geometric pattern overlay
        Opacity(
          opacity: 0.04,
          child: CustomPaint(
            painter: GeometricPatternPainter(),
            size: Size.infinite,
          ),
        ),
      ],
    );
  }
}

class Particle {
  late double x;
  late double y;
  late double size;
  late double speedX;
  late double speedY;
  late Color color;

  Particle() {
    final random = math.Random();
    x = random.nextDouble();
    y = random.nextDouble();
    size = random.nextDouble() * 5 + 1;
    speedX = (random.nextDouble() - 0.5) * 0.0003;
    speedY = (random.nextDouble() - 0.5) * 0.0003;
    
    final colors = [
      Colors.white.withValues(alpha: 0.4),
      const Color(0xFF14FFEC).withValues(alpha: 0.5),
      const Color(0xFF0D7377).withValues(alpha: 0.4),
    ];
    color = colors[random.nextInt(colors.length)];
  }

  void update() {
    x += speedX;
    y += speedY;

    if (x < 0 || x > 1) speedX *= -1;
    if (y < 0 || y > 1) speedY *= -1;

    x = x.clamp(0.0, 1.0);
    y = y.clamp(0.0, 1.0);
  }
}

class ParticlePainter extends CustomPainter {
  final List<Particle> particles;
  final double animationValue;

  ParticlePainter({
    required this.particles,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (var particle in particles) {
      particle.update();
      
      final paint = Paint()
        ..color = particle.color
        ..style = PaintingStyle.fill;

      canvas.drawCircle(
        Offset(particle.x * size.width, particle.y * size.height),
        particle.size,
        paint,
      );
      
      // Draw glow effect for bubble appearance
      final glowPaint = Paint()
        ..color = particle.color.withValues(alpha: 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      
      canvas.drawCircle(
        Offset(particle.x * size.width, particle.y * size.height),
        particle.size * 4,
        glowPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant ParticlePainter oldDelegate) {
    return true;
  }
}

// Animated circles painter for larger bubble effects
class AnimatedCirclesPainter extends CustomPainter {
  final double animationValue;

  AnimatedCirclesPainter({required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Draw multiple animated circles with different sizes and positions
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
    
    // Add some random bubble positions with pulsing effect
    final random = math.Random(42); // Fixed seed for consistency
    for (int i = 0; i < 10; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final baseRadius = 40.0 + (i * 25);
      final radius = baseRadius + (math.sin(animationValue * 2 * math.pi + i) * 15);
      
      paint.color = const Color(0xFF14FFEC).withValues(alpha: 0.03);
      canvas.drawCircle(
        Offset(x, y),
        radius,
        paint,
      );
      
      // Add inner glow for bubble effect
      paint.color = const Color(0xFF14FFEC).withValues(alpha: 0.02);
      canvas.drawCircle(
        Offset(x, y),
        radius * 0.7,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant AnimatedCirclesPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}

// Custom geometric pattern painter with bubble intersections
class GeometricPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    const spacing = 60.0;
    
    // Draw diagonal grid lines
    for (double i = -size.height; i < size.width + size.height; i += spacing) {
      canvas.drawLine(
        Offset(i, 0),
        Offset(i + size.height, size.height),
        paint,
      );
    }
    
    // Draw circles at intersections (small bubble effect)
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(
          Offset(x, y),
          2,
          Paint()
            ..color = const Color(0xFF14FFEC).withValues(alpha: 0.2)
            ..style = PaintingStyle.fill,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}