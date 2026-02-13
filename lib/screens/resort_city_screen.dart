import 'package:flutter/material.dart';
import 'package:palmnazi/screens/channel_screen.dart';
import 'package:palmnazi/widgets/animated_background.dart';
import 'package:palmnazi/models/models.dart';

class ResortCityScreen extends StatefulWidget {
  final ResortCityItem city;

  const ResortCityScreen({
    super.key,
    required this.city,
  });

  @override
  State<ResortCityScreen> createState() => _ResortCityScreenState();
}

class _ResortCityScreenState extends State<ResortCityScreen>
    with TickerProviderStateMixin {
  late ScrollController _scrollController;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  // Channels Data - This will come from backend based on city
  final List<ChannelItem> _channels = [
    ChannelItem(
      id: '1',
      icon: Icons.king_bed_outlined,
      title: 'Accommodation',
      description: 'Premium stays and luxury lodging',
      color: const Color(0xFF0D7377),
      imagePath: 'images/channels/accommodation.jpg',
      subcategories: [
        'Luxury Hotels',
        'Beach Resorts',
        'Mountain Lodges',
        'Boutique Hotels',
        'Vacation Rentals',
        'Eco-Lodges',
      ],
    ),
    ChannelItem(
      id: '2',
      icon: Icons.restaurant_menu,
      title: 'Dining',
      description: 'Culinary experiences and local cuisine',
      color: const Color(0xFFE91E63),
      imagePath: 'images/channels/dining.jpg',
      subcategories: [
        'Fine Dining',
        'Local Cuisine',
        'Seafood Restaurants',
        'Street Food',
        'Cafes & Coffee Shops',
        'Rooftop Bars',
      ],
    ),
    ChannelItem(
      id: '3',
      icon: Icons.celebration,
      title: 'Events',
      description: 'Festivals and cultural experiences',
      color: const Color(0xFFFF9800),
      imagePath: 'images/channels/events.jpg',
      subcategories: [
        'Music Festivals',
        'Cultural Ceremonies',
        'Art Exhibitions',
        'Food Festivals',
        'Sports Events',
        'Night Markets',
      ],
    ),
    ChannelItem(
      id: '4',
      icon: Icons.shopping_bag_outlined,
      title: 'Shopping',
      description: 'Markets and artisan crafts',
      color: const Color(0xFF9C27B0),
      imagePath: 'images/channels/shopping.jpg',
      subcategories: [
        'Artisan Markets',
        'Shopping Malls',
        'Craft Stores',
        'Jewelry Shops',
        'Textile Markets',
        'Souvenir Shops',
      ],
    ),
    ChannelItem(
      id: '5',
      icon: Icons.terrain,
      title: 'Adventure',
      description: 'Nature and outdoor activities',
      color: const Color(0xFF2196F3),
      imagePath: 'images/channels/adventure.jpg',
      subcategories: [
        'Safari Tours',
        'Hiking Trails',
        'Water Sports',
        'Wildlife Viewing',
        'Beach Activities',
        'Mountain Climbing',
      ],
    ),
    ChannelItem(
      id: '6',
      icon: Icons.spa_outlined,
      title: 'Wellness',
      description: 'Relaxation and rejuvenation',
      color: const Color(0xFF00897B),
      imagePath: 'images/channels/wellness.jpg',
      subcategories: [
        'Spa & Massage',
        'Yoga Retreats',
        'Wellness Centers',
        'Hot Springs',
        'Meditation Gardens',
        'Fitness Centers',
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeIn),
    );
    
    _fadeController.forward();
  }

  void _navigateToChannel(ChannelItem channel) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChannelScreen(
          city: widget.city,
          channel: channel,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const AnimatedBackground(),
          
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              // City Header
              SliverAppBar(
                expandedHeight: 300,
                pinned: true,
                backgroundColor: widget.city.color.withValues(alpha: 0.9),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(
                    widget.city.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(
                          color: Colors.black45,
                          blurRadius: 10,
                        ),
                      ],
                    ),
                  ),
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        widget.city.imagePath,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  widget.city.color,
                                  widget.city.color.withValues(alpha: 0.7),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.3),
                              Colors.black.withValues(alpha: 0.7),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              // City Info Section
              SliverToBoxAdapter(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Container(
                    margin: const EdgeInsets.all(24),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          widget.city.color.withValues(alpha: 0.3),
                          widget.city.color.withValues(alpha: 0.1),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: widget.city.color.withValues(alpha: 0.5),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.city.tagline,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF14FFEC),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          widget.city.description,
                          style: const TextStyle(
                            fontSize: 15,
                            color: Colors.white70,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              
              // Channels Section Header
              SliverToBoxAdapter(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Column(
                      children: [
                        ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [Color(0xFF14FFEC), Colors.white],
                          ).createShader(bounds),
                          child: Text(
                            'Explore Channels',
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
                          'Choose a category to discover amazing places and experiences',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              
              // Channels Grid
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 400,
                    childAspectRatio: 1.0,
                    crossAxisSpacing: 20,
                    mainAxisSpacing: 20,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      return FadeTransition(
                        opacity: _fadeAnimation,
                        child: _buildChannelCard(_channels[index]),
                      );
                    },
                    childCount: _channels.length,
                  ),
                ),
              ),
              
              // Bottom Spacing
              const SliverToBoxAdapter(
                child: SizedBox(height: 48),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChannelCard(ChannelItem channel) {
    return GestureDetector(
      onTap: () => _navigateToChannel(channel),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: channel.color.withValues(alpha: 0.4),
              blurRadius: 15,
              spreadRadius: 2,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              // Background Image or Color
              Positioned.fill(
                child: Image.asset(
                  channel.imagePath,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            channel.color.withValues(alpha: 0.8),
                            channel.color.withValues(alpha: 0.5),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              
              // Gradient Overlay
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.3),
                        Colors.black.withValues(alpha: 0.75),
                      ],
                    ),
                  ),
                ),
              ),
              
              // Content
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Icon
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.4),
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          channel.icon,
                          size: 32,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Title
                      Text(
                        channel.title,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      
                      // Description
                      Text(
                        channel.description,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 12),
                      
                      // Explore Button
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF14FFEC),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Explore',
                                  style: TextStyle(
                                    color: channel.color,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.arrow_forward,
                                  size: 14,
                                  color: channel.color,
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
}