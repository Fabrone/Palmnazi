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
        // Hero Background Image — unchanged, image source preserved
        Positioned.fill(
          child: Image.asset(
            'assets/images/hero_background.png',
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              // Fallback gradient — brighter, more vivid than the old dark navy
              return Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF0D2461), // rich deep navy  (was dull 0xFF0A1128)
                      Color(0xFF1565C0), // vibrant royal blue (was flat 0xFF1E3A5F)
                      Color(0xFF00ACC1), // vivid cyan        (was muddy 0xFF0D7377)
                      Color(0xFF0D2461), // back to rich navy (was dull 0xFF0A1128)
                    ],
                    stops: [0.0, 0.35, 0.7, 1.0],
                  ),
                ),
              );
            },
          ),
        ),
        
        // ── Overlay — SIGNIFICANTLY LIGHTENED ─────────────────────────────
        // The original alpha (0.55 / 0.65 / 0.55) smothered both the hero
        // image and every colour beneath it. Reduced to 0.28 / 0.35 / 0.28
        // so the background image breathes and accent colours pop.
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.28), // was 0.55
                  Colors.black.withValues(alpha: 0.35), // was 0.65
                  Colors.black.withValues(alpha: 0.28), // was 0.55
                ],
              ),
            ),
          ),
        ),
        
        // Animated gradient overlay — brighter, more visible sweep
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
                    const Color(0xFF00FFEA).withValues(alpha: 0.14), // was 0xFF14FFEC @ 0.06
                    const Color(0xFF00BCD4).withValues(alpha: 0.18), // was 0xFF0D7377 @ 0.08
                    const Color(0xFF00FFEA).withValues(alpha: 0.14), // was 0xFF14FFEC @ 0.06
                  ],
                ),
              ),
            );
          },
        ),
        
        // Floating particles (bubbles) — brighter colours & stronger glow
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
        
        // Subtle geometric pattern overlay — slightly more visible
        Opacity(
          opacity: 0.08, // was 0.04
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
    
    // Brighter particle colours — higher alpha for better visibility
    final colors = [
      Colors.white.withValues(alpha: 0.70),                    // was 0.4
      const Color(0xFF00FFEA).withValues(alpha: 0.80),         // was 0xFF14FFEC @ 0.5
      const Color(0xFF40C4FF).withValues(alpha: 0.65),         // was 0xFF0D7377 @ 0.4 (dull)
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
      
      // Glow effect — stronger alpha for better bubble brightness
      final glowPaint = Paint()
        ..color = particle.color.withValues(alpha: 0.30) // was 0.15
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
      
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

    // Draw multiple animated circles with brighter, more visible strokes
    for (int i = 0; i < 5; i++) {
      final radius = (size.width / 4) + (i * 50) + (animationValue * 20);
      // was: alpha: 0.05 - (i * 0.01) — too faint; now 0.12 - (i * 0.02)
      paint.color = const Color(0xFF00FFEA).withValues(alpha: 0.12 - (i * 0.02).clamp(0.0, 0.12));
      
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
    
    // Pulsing bubble positions — brighter
    final random = math.Random(42); // Fixed seed for consistency
    for (int i = 0; i < 10; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final baseRadius = 40.0 + (i * 25);
      final radius = baseRadius + (math.sin(animationValue * 2 * math.pi + i) * 15);
      
      paint.color = const Color(0xFF00FFEA).withValues(alpha: 0.07); // was 0.03
      canvas.drawCircle(
        Offset(x, y),
        radius,
        paint,
      );
      
      // Inner glow ring
      paint.color = const Color(0xFF00FFEA).withValues(alpha: 0.05); // was 0.02
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

// Custom geometric pattern painter
class GeometricPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.10) // was 0.06
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    const spacing = 60.0;
    
    // Diagonal grid lines
    for (double i = -size.height; i < size.width + size.height; i += spacing) {
      canvas.drawLine(
        Offset(i, 0),
        Offset(i + size.height, size.height),
        paint,
      );
    }
    
    // Bright intersection dots
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(
          Offset(x, y),
          2,
          Paint()
            ..color = const Color(0xFF00FFEA).withValues(alpha: 0.45) // was 0xFF14FFEC @ 0.2
            ..style = PaintingStyle.fill,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}