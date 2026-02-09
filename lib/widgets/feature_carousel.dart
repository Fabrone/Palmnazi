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
      icon: Icons.hotel,
      title: 'Luxury Hotels & Accommodations',
      description: 'Experience world-class hospitality in Kenya\'s finest resort cities. From beachfront villas to mountain lodges, discover premium accommodations that offer exceptional comfort, stunning views, and unforgettable service. Each property is carefully curated to ensure your stay exceeds expectations.',
      gradient: const LinearGradient(
        colors: [Color(0xFF0D7377), Color(0xFF1E3A5F)],
      ),
      imagePath: 'assets/images/feature_hotels.jpg',
    ),
    FeatureItem(
      icon: Icons.restaurant,
      title: 'Exquisite Dining Experiences',
      description: 'Savor the flavors of Kenya and beyond with our curated selection of world-class restaurants and local eateries. From fresh seafood by the coast to traditional Kenyan cuisine in the highlands, embark on a culinary journey that celebrates local ingredients, innovative cooking, and authentic flavors.',
      gradient: const LinearGradient(
        colors: [Color(0xFFE91E63), Color(0xFF880E4F)],
      ),
      imagePath: 'assets/images/feature_dining.jpg',
    ),
    FeatureItem(
      icon: Icons.celebration,
      title: 'Cultural Events & Festivals',
      description: 'Immerse yourself in vibrant cultural celebrations, music festivals, and traditional ceremonies that showcase Kenya\'s rich heritage. Connect with local communities, witness age-old traditions, and participate in events that bring people together. Every festival tells a unique story of Kenya\'s diverse cultures.',
      gradient: const LinearGradient(
        colors: [Color(0xFFFF9800), Color(0xFFE65100)],
      ),
      imagePath: 'assets/images/feature_events.png',
    ),
    FeatureItem(
      icon: Icons.shopping_bag,
      title: 'Artisan Markets & Shopping',
      description: 'Discover authentic Kenyan craftsmanship and unique treasures at local markets and boutiques. Support local artisans while finding one-of-a-kind souvenirs, handmade jewelry, traditional textiles, and contemporary art. Each purchase tells a story and supports sustainable tourism.',
      gradient: const LinearGradient(
        colors: [Color(0xFF9C27B0), Color(0xFF4A148C)],
      ),
      imagePath: 'assets/images/feature_shopping.jpg',
    ),
    FeatureItem(
      icon: Icons.landscape,
      title: 'Adventure & Nature Exploration',
      description: 'Explore breathtaking landscapes from pristine beaches to majestic mountains. Engage in thrilling outdoor activities including safari adventures, hiking expeditions, water sports, and wildlife encounters. Experience Kenya\'s natural beauty through sustainable and responsible tourism practices.',
      gradient: const LinearGradient(
        colors: [Color(0xFF2196F3), Color(0xFF0D47A1)],
      ),
      imagePath: 'assets/images/feature_nature.jpg',
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
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 60),
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
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Explore our comprehensive platform designed to enhance your resort city experience with curated services and authentic local connections',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 50),
          SizedBox(
            height: 480,
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
                        height: Curves.easeInOut.transform(value) * 480,
                        child: child,
                      ),
                    );
                  },
                  child: _buildFeatureCard(_features[index], index),
                );
              },
            ),
          ),
          const SizedBox(height: 30),
          _buildPageIndicator(),
        ],
      ),
    );
  }

  Widget _buildFeatureCard(FeatureItem feature, int index) {
    return GestureDetector(
      onTap: () => widget.onFeatureTap(feature.title),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: feature.gradient.colors.first.withValues(alpha: 0.4),
              blurRadius: 25,
              spreadRadius: 3,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
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
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          gradient: feature.gradient,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: feature.gradient.colors.first.withValues(alpha: 0.6),
                              blurRadius: 20,
                              spreadRadius: 3,
                            ),
                          ],
                        ),
                        child: Icon(
                          feature.icon,
                          size: 36,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        feature.title,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        feature.description,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.95),
                          height: 1.6,
                        ),
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF14FFEC),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  'Learn More',
                                  style: TextStyle(
                                    color: feature.gradient.colors.last,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.arrow_forward,
                                  size: 16,
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
          width: _currentPage == index ? 40 : 10,
          height: 10,
          decoration: BoxDecoration(
            gradient: _currentPage == index
                ? const LinearGradient(
                    colors: [Color(0xFF14FFEC), Color(0xFF0D7377)],
                  )
                : null,
            color: _currentPage == index
                ? null
                : Colors.white.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(5),
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

  FeatureItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.gradient,
    required this.imagePath,
  });
}