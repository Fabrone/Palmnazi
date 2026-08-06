import 'package:flutter/material.dart';
import 'dart:async';
import 'package:palmnazi/services/app_colors.dart';
import 'package:palmnazi/services/app_strings.dart';

class FeatureCarousel extends StatefulWidget {
  final Function(String) onFeatureTap;

  const FeatureCarousel({
    super.key,
    required this.onFeatureTap,
  });

  @override
  State<FeatureCarousel> createState() => _FeatureCarouselState();
}

class _FeatureCarouselState extends State<FeatureCarousel> {
  late PageController _pageController;
  int _currentPage = 0;
  Timer? _timer;

  List<FeatureItem> _features(BuildContext context) => [
        FeatureItem(
          icon: Icons.king_bed_outlined,
          title: context.tr('widget_feature_carousel_accommodation_title'),
          description: context.tr('widget_feature_carousel_accommodation_desc'),
          gradient: LinearGradient(
            colors: [AC.tealDark, AC.surface],
          ),
          imagePath: 'assets/images/feature_accommodation.png',
          channelName: 'Accommodation',
        ),
        FeatureItem(
          icon: Icons.restaurant_menu,
          title: context.tr('widget_feature_carousel_dining_title'),
          description: context.tr('widget_feature_carousel_dining_desc'),
          gradient: const LinearGradient(
            colors: [Color(0xFFE91E63), Color(0xFF880E4F)],
          ),
          imagePath: 'assets/images/feature_dining.jpg',
          channelName: 'Dining',
        ),
        FeatureItem(
          icon: Icons.celebration,
          title: context.tr('widget_feature_carousel_events_title'),
          description: context.tr('widget_feature_carousel_events_desc'),
          gradient: LinearGradient(
            colors: [AC.orange, const Color(0xFFE65100)],
          ),
          imagePath: 'assets/images/feature_events.png',
          channelName: 'Events',
        ),
        FeatureItem(
          icon: Icons.shopping_bag_outlined,
          title: context.tr('widget_feature_carousel_shopping_title'),
          description: context.tr('widget_feature_carousel_shopping_desc'),
          gradient: const LinearGradient(
            colors: [Color(0xFF9C27B0), Color(0xFF4A148C)],
          ),
          imagePath: 'assets/images/feature_shopping.jpg',
          channelName: 'Shopping',
        ),
        FeatureItem(
          icon: Icons.terrain,
          title: context.tr('widget_feature_carousel_adventure_title'),
          description: context.tr('widget_feature_carousel_adventure_desc'),
          gradient: const LinearGradient(
            colors: [Color(0xFF2196F3), Color(0xFF0D47A1)],
          ),
          imagePath: 'assets/images/feature_nature.jpg',
          channelName: 'Adventure',
        ),
      ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.85);
    _startAutoScroll();
  }

  void _startAutoScroll() {
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_currentPage < _features(context).length - 1) {
        _currentPage++;
      } else {
        _currentPage = 0;
      }

      if (_pageController.hasClients) {
        _pageController.animateToPage(
          _currentPage,
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final carouselHeight = (screenHeight * 0.5).clamp(350.0, 450.0);

    final features = _features(context);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 30, horizontal: 0),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                ShaderMask(
                  // Gradient goes teal -> AC.textPri (not a hardcoded white)
                  // so the trailing end of the headline stays visible
                  // against a light page background.
                  shaderCallback: (bounds) => LinearGradient(
                    colors: [AC.teal, AC.textPri],
                  ).createShader(bounds),
                  child: Text(
                    context.tr('widget_feature_carousel_title'),
                    // NOTE: required by ShaderMask's default
                    // BlendMode.modulate — the shader above supplies the
                    // real, theme-aware colors; changing this would tint
                    // them.
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  context.tr('widget_feature_carousel_subtitle'),
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontSize: 14,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          SizedBox(
            height: carouselHeight,
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() {
                  _currentPage = index;
                });
              },
              itemCount: features.length,
              itemBuilder: (context, index) {
                return AnimatedBuilder(
                  animation: _pageController,
                  builder: (context, child) {
                    double value = 1.0;
                    if (_pageController.position.haveDimensions) {
                      value = _pageController.page! - index;
                      value = (1 - (value.abs() * 0.3)).clamp(0.0, 1.0);
                    }
                    return Center(
                      child: SizedBox(
                        height:
                            Curves.easeInOut.transform(value) * carouselHeight,
                        child: child,
                      ),
                    );
                  },
                  child: _buildFeatureCard(features[index], index),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          _buildPageIndicator(features.length),
        ],
      ),
    );
  }

  Widget _buildFeatureCard(FeatureItem feature, int index) {
    return GestureDetector(
      onTap: () => widget.onFeatureTap(feature.channelName),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: feature.gradient.colors.first.withValues(alpha: 0.4),
              blurRadius: 20,
              spreadRadius: 2,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              // Background Image or Gradient
              Positioned.fill(
                child: Image.asset(
                  feature.imagePath,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      decoration: BoxDecoration(
                        gradient: feature.gradient,
                      ),
                    );
                  },
                ),
              ),

              // Dark Gradient Overlay
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.3),
                        Colors.black.withValues(alpha: 0.85),
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
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: feature.gradient,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: feature.gradient.colors.first
                                  .withValues(alpha: 0.6),
                              blurRadius: 15,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Icon(
                          feature.icon,
                          size: 28,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        feature.title,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        feature.description,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.95),
                          height: 1.5,
                        ),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: AC.teal,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  context.tr(
                                      'widget_feature_carousel_explore_cta'),
                                  style: TextStyle(
                                    color: feature.gradient.colors.last,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.arrow_forward,
                                  size: 14,
                                  color: feature.gradient.colors.last,
                                ),
                              ],
                            ),
                          ),
                        ],
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

  Widget _buildPageIndicator(int featureCount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        featureCount,
        (index) => AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: _currentPage == index ? 32 : 8,
          height: 8,
          decoration: BoxDecoration(
            gradient: _currentPage == index
                ? LinearGradient(
                    colors: [AC.teal, AC.tealDark],
                  )
                : null,
            color: _currentPage == index ? null : AC.overlay(0.3),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}

class FeatureItem {
  final IconData icon;
  final String title;
  final String description;
  final Gradient gradient;
  final String imagePath;
  final String channelName;

  FeatureItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.gradient,
    required this.imagePath,
    required this.channelName,
  });
}
