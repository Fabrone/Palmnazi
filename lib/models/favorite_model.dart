import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FavoriteModel
//
// Firestore collection : Favorites
// Document ID          : {firebaseUid}_{placeId}  (deterministic — enforced
//                         by firestore.rules so a tourist can only ever have
//                         one favorite doc per place, and toggling is a
//                         plain create/delete, never an update)
// ─────────────────────────────────────────────────────────────────────────────

class FavoriteModel {
  final String id;
  final String firebaseUid;
  final String placeId;
  final String placeName;
  final String? placeCoverImage;
  final String cityId;
  final String cityName;
  final DateTime? createdAt;

  const FavoriteModel({
    required this.id,
    required this.firebaseUid,
    required this.placeId,
    required this.placeName,
    this.placeCoverImage,
    required this.cityId,
    required this.cityName,
    this.createdAt,
  });

  factory FavoriteModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return FavoriteModel(
      id: doc.id,
      firebaseUid: d['firebaseUid'] as String? ?? '',
      placeId: d['placeId'] as String? ?? '',
      placeName: d['placeName'] as String? ?? '',
      placeCoverImage: d['placeCoverImage'] as String?,
      cityId: d['cityId'] as String? ?? '',
      cityName: d['cityName'] as String? ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toCreateMap() => {
        'firebaseUid': firebaseUid,
        'placeId': placeId,
        'placeName': placeName,
        'placeCoverImage': placeCoverImage,
        'cityId': cityId,
        'cityName': cityName,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
