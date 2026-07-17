import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:palmnazi/models/category_model.dart';
import 'package:palmnazi/models/city_model.dart';
import 'package:palmnazi/models/favorite_model.dart';
import 'package:palmnazi/screens/place_details_screen.dart';
import 'package:palmnazi/services/favorite_service.dart';
import 'package:palmnazi/services/place_lookup_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MyFavoritesScreen
//
// Lists the signed-in tourist's own favorited places (Firestore Favorites
// collection, filtered by firebaseUid via Firestore security rules).
// Reachable from AccountScreen. A place is favorited/unfavorited from the
// heart icon on place_details_screen.dart, not from here — tapping a card
// re-fetches the full place record (only a lean snapshot is stored) and
// opens PlaceDetailsScreen.
// ─────────────────────────────────────────────────────────────────────────────

abstract final class _P {
  static const Color aquaBright = Color(0xFF00E5FF);
  static const Color deepNavy = Color(0xFF01263F);
  static const Color deepBlue = Color(0xFF071829);
}

class MyFavoritesScreen extends StatelessWidget {
  const MyFavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: _P.deepBlue,
      appBar: AppBar(
        backgroundColor: _P.deepNavy,
        title:
            const Text('My Favorites', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: uid == null
          ? const Center(
              child: Text('Sign in to view your favorites.',
                  style: TextStyle(color: Colors.white54)))
          : StreamBuilder<List<FavoriteModel>>(
              stream: FavoriteService.streamForUser(uid),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(color: _P.aquaBright));
                }
                if (snap.hasError) {
                  return Center(
                    child: Text('Could not load favorites: ${snap.error}',
                        style: const TextStyle(color: Colors.white54)),
                  );
                }
                final favorites = snap.data ?? const <FavoriteModel>[];
                if (favorites.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No favorites yet. Tap the heart icon on any listing to save it here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white54),
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: favorites.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _FavoriteCard(favorite: favorites[i]),
                );
              },
            ),
    );
  }
}

class _FavoriteCard extends StatefulWidget {
  final FavoriteModel favorite;
  const _FavoriteCard({required this.favorite});

  @override
  State<_FavoriteCard> createState() => _FavoriteCardState();
}

class _FavoriteCardState extends State<_FavoriteCard> {
  bool _opening = false;

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    final place = await PlaceLookupService.fetchPlace(widget.favorite.placeId);
    if (!mounted) return;
    setState(() => _opening = false);
    if (place == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This place is no longer available.')),
      );
      return;
    }
    final city = CityModel(
      id: widget.favorite.cityId,
      name: widget.favorite.cityName,
      slug: '',
      country: '',
      region: '',
      latitude: 0,
      longitude: 0,
      coverImage: '',
      description: '',
      isActive: true,
      totalPlaces: 0,
      totalEvents: 0,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final category = place.categoryLinks.isNotEmpty
        ? CategoryModel(
            id: place.categoryLinks.first.categoryId,
            name: place.categoryLinks.first.categoryName,
            slug: '',
            isActive: true,
            children: const [],
            sortOrder: 0,
          )
        : CategoryModel(
            id: '',
            name: '',
            slug: '',
            isActive: true,
            children: const [],
            sortOrder: 0,
          );
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PlaceDetailsScreen(city: city, category: category, place: place),
      ),
    );
  }

  Future<void> _remove() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FavoriteService.remove(uid, widget.favorite.placeId);
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.favorite;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _P.aquaBright.withValues(alpha: 0.25)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _open,
          borderRadius: BorderRadius.circular(14),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: (f.placeCoverImage ?? '').isNotEmpty
                    ? Image.network(
                        f.placeCoverImage!,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _placeholderThumb(),
                      )
                    : _placeholderThumb(),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(f.placeName,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(f.cityName,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),
              if (_opening)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      color: _P.aquaBright, strokeWidth: 2),
                )
              else
                IconButton(
                  onPressed: _remove,
                  tooltip: 'Remove from favorites',
                  icon: const Icon(Icons.favorite,
                      color: Color(0xFFFF6B6B), size: 22),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholderThumb() => Container(
        width: 64,
        height: 64,
        color: Colors.white10,
        child: const Icon(Icons.place_outlined, color: Colors.white38),
      );
}
