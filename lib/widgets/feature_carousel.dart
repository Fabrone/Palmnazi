import 'package:flutter/material.dart';
import 'dart:async';

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

  final List<FeatureItem> _features = [
    FeatureItem(
      icon: Icons.king_bed_outlined,
      title: 'Premium Accommodation',
      description: 'Experience world-class hospitality in Kenya\'s finest resort cities. From luxurious beachfront villas to serene mountain lodges, discover handpicked accommodations that offer exceptional comfort, breathtaking views, and personalized service.',
      gradient: const LinearGradient(
        colors: [Color(0xFF0D7377), Color(0xFF1E3A5F)],
      ),
      imagePath: 'assets/images/feature_accommodation.png',
      channelName: 'Accommodation',
    ),
    FeatureItem(
      icon: Icons.restaurant_menu,
      title: 'Exquisite Dining',
      description: 'Embark on a culinary adventure through Kenya with our curated collection of world-class restaurants and authentic local eateries. From fresh ocean catches to traditional Kenyan delicacies, savor dishes crafted with passion.',
      gradient: const LinearGradient(
        colors: [Color(0xFFE91E63), Color(0xFF880E4F)],
      ),
      imagePath: 'assets/images/feature_dining.jpg',
      channelName: 'Dining',
    ),
    FeatureItem(
      icon: Icons.celebration,
      title: 'Cultural Events',
      description: 'Immerse yourself in vibrant cultural celebrations, music festivals, and traditional ceremonies. Connect with local communities, witness age-old traditions, and participate in events that unite people across cultures.',
      gradient: const LinearGradient(
        colors: [Color(0xFFFF9800), Color(0xFFE65100)],
      ),
      imagePath: 'assets/images/feature_events.png',
      channelName: 'Events',
    ),
    FeatureItem(
      icon: Icons.shopping_bag_outlined,
      title: 'Artisan Shopping',
      description: 'Discover authentic Kenyan craftsmanship at vibrant local markets and boutique shops. Find one-of-a-kind souvenirs, handcrafted jewelry, traditional textiles, and contemporary art that tells a meaningful story.',
      gradient: const LinearGradient(
        colors: [Color(0xFF9C27B0), Color(0xFF4A148C)],
      ),
      imagePath: 'assets/images/feature_shopping.jpg',
      channelName: 'Shopping',
    ),
    FeatureItem(
      icon: Icons.terrain,
      title: 'Adventure & Nature',
      description: 'Explore breathtaking landscapes from pristine beaches to majestic mountains. Engage in safari adventures, mountain hiking, water sports, and unforgettable wildlife encounters through sustainable tourism.',
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
      if (_currentPage < _features.length - 1) {
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
    
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 30, horizontal: 0),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Color(0xFF14FFEC), Colors.white],
                  ).createShader(bounds),
                  child: Text(
                    'What We Offer',
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
                  'Explore curated services for an unforgettable resort experience',
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
              itemCount: _features.length,
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
                        height: Curves.easeInOut.transform(value) * carouselHeight,
                        child: child,
                      ),
                    );
                  },
                  child: _buildFeatureCard(_features[index], index),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          _buildPageIndicator(),
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
                              color: feature.gradient.colors.first.withValues(alpha: 0.6),
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
                              color: const Color(0xFF14FFEC),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  'Explore',
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

  Widget _buildPageIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        _features.length,
        (index) => AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: _currentPage == index ? 32 : 8,
          height: 8,
          decoration: BoxDecoration(
            gradient: _currentPage == index
                ? const LinearGradient(
                    colors: [Color(0xFF14FFEC), Color(0xFF0D7377)],
                  )
                : null,
            color: _currentPage == index
                ? null
                : Colors.white.withValues(alpha: 0.3),
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