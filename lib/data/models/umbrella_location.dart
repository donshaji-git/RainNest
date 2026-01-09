import 'package:cloud_firestore/cloud_firestore.dart';

class UmbrellaLocation {
  final String id;
  final String machineName;
  final String description;
  final double latitude;
  final double longitude;
  final int totalSlots;
  final List<String> slotIds;
  final DateTime createdAt;

  UmbrellaLocation({
    required this.id,
    required this.machineName,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.totalSlots,
    required this.slotIds,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'machineName': machineName,
      'description': description,
      'latitude': latitude,
      'longitude': longitude,
      'totalSlots': totalSlots,
      'slotIds': slotIds,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory UmbrellaLocation.fromMap(Map<String, dynamic> map, String id) {
    return UmbrellaLocation(
      id: id,
      machineName: map['machineName'] ?? '',
      description: map['description'] ?? '',
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      totalSlots: map['totalSlots'] ?? 0,
      slotIds: List<String>.from(map['slotIds'] ?? []),
      createdAt: (map['createdAt'] as Timestamp).toDate(),
    );
  }
}
