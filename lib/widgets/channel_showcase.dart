import 'package:flutter/material.dart';

class ChannelShowcase extends StatefulWidget {
  final Function(String) onChannelTap;

  const ChannelShowcase({
    super.key,
    required this.onChannelTap,
  });

  @override
  State<ChannelShowcase> createState() => _ChannelShowcaseState();
}

class _ChannelShowcaseState extends State<ChannelShowcase>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  int _hoveredIndex = -1;

  final List<ChannelItem> _channels = [
    ChannelItem(
      icon: Icons.hotel_outlined,
      title: 'Hotels',
      description: 'Premium stays',
      color: const Color(0xFF00897B),
    ),
    ChannelItem(
      icon: Icons.restaurant_outlined,
      title: 'Restaurants',
      description: 'Fine dining',
      color: const Color(0xFFE91E63),
    ),
    ChannelItem(
      icon: Icons.celebration_outlined,
      title: 'Events',
      description: 'Cultural activities',
      color: const Color(0xFFFF9800),
    ),
    ChannelItem(
      icon: Icons.shopping_bag_outlined,
      title: 'Shopping',
      description: 'Local markets',
      color: const Color(0xFF9C27B0),
    ),
    ChannelItem(
      icon: Icons.spa_outlined,
      title: 'Wellness',
      description: 'Spas & relaxation',
      color: const Color(0xFF2196F3),
    ),
    ChannelItem(
      icon: Icons.sports_soccer_outlined,
      title: 'Activities',
      description: 'Sports & recreation',
      color: const Color(0xFF4CAF50),
    ),
    ChannelItem(
      icon: Icons.nightlife_outlined,
      title: 'Nightlife',
      description: 'Bars & clubs',
      color: const Color(0xFFFF5722),
    ),
    ChannelItem(
      icon: Icons.beach_access_outlined,
      title: 'Beaches',
      description: 'Coastal paradise',
      color: const Color(0xFF00BCD4),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isLargeScreen = screenWidth > 1200;
    final isMediumScreen = screenWidth > 800;
    
    int crossAxisCount = isLargeScreen ? 4 : (isMediumScreen ? 3 : 2);

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(
            'Explore Our Channels',
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
              fontSize: 42,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'Everything you need for an unforgettable resort experience',
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          LayoutBuilder(
            builder: (context, constraints) {
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1.0,
                ),
                itemCount: _channels.length,
                itemBuilder: (context, index) {
                  return TweenAnimationBuilder<double>(
                    duration: Duration(milliseconds: 500 + (index * 100)),
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
                    child: _buildChannelCard(_channels[index], index),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildChannelCard(ChannelItem channel, int index) {
    final isHovered = _hoveredIndex == index;

    return MouseRegion(
      onEnter: (_) {
        setState(() {
          _hoveredIndex = index;
        });
        _animationController.forward();
      },
      onExit: (_) {
        setState(() {
          _hoveredIndex = -1;
        });
        _animationController.reverse();
      },
      child: GestureDetector(
        onTap: () => widget.onChannelTap(channel.title),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          transform: Matrix4.identity()
            ..setTranslationRaw(0.0, isHovered ? -8.0 : 0.0, 0.0)
            ..multiply(Matrix4.diagonal3Values(
                isHovered ? 1.05 : 1.0,
                isHovered ? 1.05 : 1.0,
                1.0,
              )),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                channel.color.withValues(alpha: isHovered ? 0.9 : 0.7),
                channel.color.withValues(alpha: isHovered ? 0.7 : 0.5),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: channel.color.withValues(alpha: isHovered ? 0.5 : 0.3),
                blurRadius: isHovered ? 30 : 15,
                spreadRadius: isHovered ? 5 : 0,
                offset: Offset(0, isHovered ? 15 : 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              children: [
                // Decorative background pattern
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.1,
                    child: CustomPaint(
                      painter: PatternPainter(),
                    ),
                  ),
                ),
                
                // Content
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3),
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          channel.icon,
                          size: 48,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        channel.title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        channel.description,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      AnimatedOpacity(
                        opacity: isHovered ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 300),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Explore',
                                style: TextStyle(
                                  color: channel.color,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.arrow_forward,
                                size: 14,
                                color: channel.color,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ChannelItem {
  final IconData icon;
  final String title;
  final String description;
  final Color color;

  ChannelItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });
}

class PatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.1)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    for (var i = 0; i < 10; i++) {
      canvas.drawCircle(
        Offset(size.width * 0.8, size.height * 0.2),
        i * 20.0,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}