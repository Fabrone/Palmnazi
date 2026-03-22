import 'package:flutter/material.dart';

abstract final class _SC {
  static const Color aquaBright = Color(0xFF00E5FF);
  static const Color teal       = Color(0xFF00838F);
}

class StatsCounter extends StatefulWidget {
  const StatsCounter({super.key});

  @override
  State<StatsCounter> createState() => _StatsCounterState();
}

class _StatsCounterState extends State<StatsCounter> {
  bool _hasAnimated = false;

  final List<StatItem> _stats = [
    StatItem(icon: Icons.location_city, count: 15,    label: 'Resort Cities',  suffix: '+'),
    StatItem(icon: Icons.business,      count: 500,   label: 'Businesses',     suffix: '+'),
    StatItem(icon: Icons.people,        count: 10000, label: 'Happy Visitors', suffix: '+'),
    StatItem(icon: Icons.star,          count: 4,     label: 'Average Rating', suffix: '.8', decimal: true),
  ];

  @override
  void initState() {
    super.initState();
    // Trigger animation once after first frame — no MediaQuery, no
    // VisibilityDetector, no window size dependency.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_hasAnimated) {
        setState(() => _hasAnimated = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double w        = constraints.maxWidth;
        final bool   isLarge  = w > 1200;
        final bool   isMedium = w > 700;

        final double hPad = isLarge ? 32 : isMedium ? 24 : 16;
        final double vPad = isLarge ? 28 : isMedium ? 24 : 18;

        final List<Widget> items = _stats
            .map((s) => Expanded(child: _buildStatItem(s, isLarge, isMedium)))
            .toList();

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
          padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xCC00838F),
                Color(0xCC005F6B),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: _SC.aquaBright.withValues(alpha: 0.35),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: _SC.teal.withValues(alpha: 0.45),
                blurRadius: 36,
                spreadRadius: 4,
              ),
            ],
          ),
          // Always horizontal — Column only on very narrow phones
          child: w < 360
              ? Column(
                  children: _stats
                      .asMap()
                      .entries
                      .map((e) => Padding(
                            padding: EdgeInsets.only(
                                bottom: e.key < _stats.length - 1 ? 28 : 0),
                            child: _buildStatItem(e.value, isLarge, isMedium),
                          ))
                      .toList(),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: items,
                ),
        );
      },
    );
  }

  Widget _buildStatItem(StatItem stat, bool isLarge, bool isMedium) {
    final double iconContainerSize = isLarge ? 48 : isMedium ? 44 : 38;
    final double iconSize          = isLarge ? 22 : isMedium ? 20 : 18;
    final double iconPad           = isLarge ? 10 : isMedium ? 10 : 8;
    final double counterSize       = isLarge ? 30 : isMedium ? 26 : 22;
    final double labelSize         = isLarge ? 13 : isMedium ? 12 : 11;
    final double spacingAbove      = isLarge ? 10 : isMedium ? 8  : 6;
    final double spacingBelowNum   = isLarge ? 4  : isMedium ? 4  : 3;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon orb
          Container(
            width: iconContainerSize,
            height: iconContainerSize,
            padding: EdgeInsets.all(iconPad),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
              border: Border.all(
                color: _SC.aquaBright.withValues(alpha: 0.60),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: _SC.aquaBright.withValues(alpha: 0.25),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Icon(stat.icon, size: iconSize, color: Colors.white),
          ),

          SizedBox(height: spacingAbove),

          // Animated number
          AnimatedCounter(
            count:         stat.count,
            duration:      const Duration(seconds: 2),
            suffix:        stat.suffix,
            decimal:       stat.decimal,
            shouldAnimate: _hasAnimated,
            fontSize:      counterSize,
          ),

          SizedBox(height: spacingBelowNum),

          // Label
          Text(
            stat.label,
            style: TextStyle(
              fontSize:      labelSize,
              color:         Colors.white.withValues(alpha: 0.92),
              fontWeight:    FontWeight.w600,
              letterSpacing: 0.3,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ── AnimatedCounter ──────────────────────────────────────────────────────────

class AnimatedCounter extends StatefulWidget {
  final int      count;
  final Duration duration;
  final String   suffix;
  final bool     decimal;
  final bool     shouldAnimate;
  final double   fontSize;

  const AnimatedCounter({
    super.key,
    required this.count,
    required this.duration,
    this.suffix        = '',
    this.decimal       = false,
    required this.shouldAnimate,
    this.fontSize      = 48,
  });

  @override
  State<AnimatedCounter> createState() => _AnimatedCounterState();
}

class _AnimatedCounterState extends State<AnimatedCounter>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double>   _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: widget.duration, vsync: this);
    _animation  = Tween<double>(begin: 0, end: widget.count.toDouble())
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
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
      builder: (context, _) {
        final String value = widget.decimal
            ? _animation.value.toStringAsFixed(1)
            : _animation.value.toInt().toString();

        return ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Colors.white, _SC.aquaBright],
          ).createShader(bounds),
          child: Text(
            '$value${widget.suffix}',
            style: TextStyle(
              fontSize:   widget.fontSize,
              fontWeight: FontWeight.bold,
              color:      Colors.white,
            ),
          ),
        );
      },
    );
  }
}

// ── Data model ───────────────────────────────────────────────────────────────

class StatItem {
  final IconData icon;
  final int      count;
  final String   label;
  final String   suffix;
  final bool     decimal;

  StatItem({
    required this.icon,
    required this.count,
    required this.label,
    this.suffix  = '',
    this.decimal = false,
  });
}