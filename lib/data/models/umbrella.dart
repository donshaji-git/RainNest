import 'package:cloud_firestore/cloud_firestore.dart';

class Umbrella {
  final String umbrellaId; // Resistance value from NodeMCU
  final String? stationId;
  final String status; // 'available', 'rented', 'maintenance'
  final DateTime createdAt;

  Umbrella({
    required this.umbrellaId,
    this.stationId,
    required this.status,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'umbrellaId': umbrellaId,
      'stationId': stationId,
      'status': status,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory Umbrella.fromMap(Map<String, dynamic> data) {
    return Umbrella(
      umbrellaId: data['umbrellaId'] ?? '',
      stationId: data['stationId'],
      status: data['status'] ?? 'available',
      createdAt: (data['createdAt'] is Timestamp)
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }
}
