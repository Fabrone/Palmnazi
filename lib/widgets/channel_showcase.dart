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

class _ChannelShowcaseState extends State<ChannelShowcase> {
  String? _expandedChannel;

  final List<ChannelItem> _channels = [
    ChannelItem(
      icon: Icons.king_bed_outlined,
      title: 'Accommodation',
      description: 'Premium stays and luxury lodging',
      color: const Color(0xFF0D7377),
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
      icon: Icons.restaurant_menu,
      title: 'Dining',
      description: 'Culinary experiences and local cuisine',
      color: const Color(0xFFE91E63),
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
      icon: Icons.celebration,
      title: 'Events',
      description: 'Festivals and cultural experiences',
      color: const Color(0xFFFF9800),
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
      icon: Icons.shopping_bag_outlined,
      title: 'Shopping',
      description: 'Markets and artisan crafts',
      color: const Color(0xFF9C27B0),
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
      icon: Icons.terrain,
      title: 'Adventure',
      description: 'Nature and outdoor activities',
      color: const Color(0xFF2196F3),
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
      icon: Icons.spa_outlined,
      title: 'Wellness',
      description: 'Relaxation and rejuvenation',
      color: const Color(0xFF00897B),
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
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        children: [
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Color(0xFF14FFEC), Colors.white],
            ).createShader(bounds),
            child: Text(
              'Explore Our Channels',
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    fontSize: 42,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Browse through our carefully curated categories to find exactly what you\'re looking for',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontSize: 16,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          LayoutBuilder(
            builder: (context, constraints) {
              final isLargeScreen = constraints.maxWidth > 1200;
              final isMediumScreen = constraints.maxWidth > 800;
              
              final crossAxisCount = isLargeScreen ? 3 : (isMediumScreen ? 2 : 1);
              
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: 1.1,
                  crossAxisSpacing: 20,
                  mainAxisSpacing: 20,
                ),
                itemCount: _channels.length,
                itemBuilder: (context, index) {
                  return _buildChannelCard(_channels[index]);
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildChannelCard(ChannelItem channel) {
    final isExpanded = _expandedChannel == channel.title;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _expandedChannel = isExpanded ? null : channel.title;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              channel.color.withValues(alpha: 0.8),
              channel.color.withValues(alpha: 0.5),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isExpanded 
                ? const Color(0xFF14FFEC) 
                : Colors.white.withValues(alpha: 0.2),
            width: isExpanded ? 3 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: channel.color.withValues(alpha: isExpanded ? 0.5 : 0.3),
              blurRadius: isExpanded ? 30 : 15,
              spreadRadius: isExpanded ? 5 : 0,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            children: [
              // Header Section
              Container(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // Icon with background
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        channel.icon,
                        size: 40,
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
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    
                    // Description
                    Text(
                      channel.description,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              
              // Dropdown indicator
              Icon(
                isExpanded 
                    ? Icons.keyboard_arrow_up 
                    : Icons.keyboard_arrow_down,
                color: Colors.white,
                size: 28,
              ),
              
              // Expandable subcategories
              if (isExpanded) ...[
                const SizedBox(height: 8),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(20),
                        bottomRight: Radius.circular(20),
                      ),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: channel.subcategories.map((subcategory) {
                          return _buildSubcategoryChip(subcategory, channel);
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ] else ...[
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    'Tap to explore',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.7),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubcategoryChip(String subcategory, ChannelItem channel) {
    return InkWell(
      onTap: () => widget.onChannelTap('${channel.title} - $subcategory'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.arrow_forward_ios,
              size: 10,
              color: const Color(0xFF14FFEC),
            ),
            const SizedBox(width: 6),
            Text(
              subcategory,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
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
  final List<String> subcategories;

  ChannelItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    required this.subcategories,
  });
}