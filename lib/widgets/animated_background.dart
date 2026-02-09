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

    // Initialize particles
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
        // Base gradient background - Improved colors
        Container(
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
        ),
        
        // Animated gradient overlay
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
                    const Color(0xFF14FFEC).withValues(alpha: 0.08),
                    const Color(0xFF0D7377).withValues(alpha: 0.12),
                    const Color(0xFF14FFEC).withValues(alpha: 0.08),
                  ],
                ),
              ),
            );
          },
        ),
        
        // Floating particles
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
        
        // Subtle geometric pattern overlay
        Opacity(
          opacity: 0.05,
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
      
      // Draw glow effect
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

// Custom geometric pattern painter
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
    
    // Draw circles at intersections
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