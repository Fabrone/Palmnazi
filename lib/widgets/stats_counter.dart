import 'package:flutter/material.dart';

class StatsCounter extends StatefulWidget {
  const StatsCounter({super.key});

  @override
  State<StatsCounter> createState() => _StatsCounterState();
}

class _StatsCounterState extends State<StatsCounter> {
  bool _hasAnimated = false;

  final List<StatItem> _stats = [
    StatItem(
      icon: Icons.location_city,
      count: 15,
      label: 'Resort Cities',
      suffix: '+',
    ),
    StatItem(
      icon: Icons.business,
      count: 500,
      label: 'Businesses',
      suffix: '+',
    ),
    StatItem(
      icon: Icons.people,
      count: 10000,
      label: 'Happy Visitors',
      suffix: '+',
    ),
    StatItem(
      icon: Icons.star,
      count: 4,
      label: 'Average Rating',
      suffix: '.8',
      decimal: true,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isLargeScreen = screenWidth > 1200;
    final isMediumScreen = screenWidth > 800;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1A237E).withValues(alpha: 0.8),
            const Color(0xFF00897B).withValues(alpha: 0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00897B).withValues(alpha: 0.3),
            blurRadius: 30,
            spreadRadius: 5,
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (isLargeScreen || isMediumScreen) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: _stats
                  .map((stat) => Expanded(
                        child: _buildStatItem(stat),
                      ))
                  .toList(),
            );
          } else {
            return Column(
              children: _stats
                  .asMap()
                  .entries
                  .map((entry) => Padding(
                        padding: EdgeInsets.only(
                          bottom: entry.key < _stats.length - 1 ? 32 : 0,
                        ),
                        child: _buildStatItem(entry.value),
                      ))
                  .toList(),
            );
          }
        },
      ),
    );
  }

  Widget _buildStatItem(StatItem stat) {
    return VisibilityDetector(
      key: Key(stat.label),
      onVisibilityChanged: (info) {
        if (info.visibleFraction > 0.5 && !_hasAnimated) {
          setState(() {
            _hasAnimated = true;
          });
        }
      },
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            child: Icon(
              stat.icon,
              size: 40,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          AnimatedCounter(
            count: stat.count,
            duration: const Duration(seconds: 2),
            suffix: stat.suffix,
            decimal: stat.decimal,
            shouldAnimate: _hasAnimated,
          ),
          const SizedBox(height: 8),
          Text(
            stat.label,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.white70,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class AnimatedCounter extends StatefulWidget {
  final int count;
  final Duration duration;
  final String suffix;
  final bool decimal;
  final bool shouldAnimate;

  const AnimatedCounter({
    super.key,
    required this.count,
    required this.duration,
    this.suffix = '',
    this.decimal = false,
    required this.shouldAnimate,
  });

  @override
  State<AnimatedCounter> createState() => _AnimatedCounterState();
}

class _AnimatedCounterState extends State<AnimatedCounter>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );

    _animation = Tween<double>(
      begin: 0,
      end: widget.count.toDouble(),
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));
  }

  @override
  void didUpdateWidget(AnimatedCounter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shouldAnimate && !oldWidget.shouldAnimate) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        String value = widget.decimal
            ? _animation.value.toStringAsFixed(1)
            : _animation.value.toInt().toString();
        
        return ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [
              Colors.white,
              Color(0xFF00897B),
            ],
          ).createShader(bounds),
          child: Text(
            '$value${widget.suffix}',
            style: const TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        );
      },
    );
  }
}

class StatItem {
  final IconData icon;
  final int count;
  final String label;
  final String suffix;
  final bool decimal;

  StatItem({
    required this.icon,
    required this.count,
    required this.label,
    this.suffix = '',
    this.decimal = false,
  });
}

// Simple visibility detector implementation
class VisibilityDetector extends StatefulWidget {
  final Widget child;
  final Function(VisibilityInfo) onVisibilityChanged;

  const VisibilityDetector({
    required super.key,
    required this.child,
    required this.onVisibilityChanged,
  });

  @override
  State<VisibilityDetector> createState() => _VisibilityDetectorState();
}

class _VisibilityDetectorState extends State<VisibilityDetector> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkVisibility();
    });
  }

  void _checkVisibility() {
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize) {
      final position = renderBox.localToGlobal(Offset.zero);
      final size = renderBox.size;
      final screenHeight = MediaQuery.of(context).size.height;

      final visibleHeight = size.height -
          (position.dy < 0 ? -position.dy : 0) -
          (position.dy + size.height > screenHeight
              ? position.dy + size.height - screenHeight
              : 0);

      final visibleFraction = visibleHeight / size.height;

      widget.onVisibilityChanged(VisibilityInfo(
        visibleFraction: visibleFraction.clamp(0.0, 1.0),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class VisibilityInfo {
  final double visibleFraction;

  VisibilityInfo({required this.visibleFraction});
}