import 'package:cloud_firestore/cloud_firestore.dart';

class Umbrella {
  final String umbrellaId;
  final double resistance; // Resistance value in Ohms
  final String? stationId;
  final String status; // 'available', 'rented', 'maintenance'
  final DateTime createdAt;

  Umbrella({
    required this.umbrellaId,
    required this.resistance,
    this.stationId,
    required this.status,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'umbrellaId': umbrellaId,
      'resistance': resistance,
      'stationId': stationId,
      'status': status,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory Umbrella.fromMap(Map<String, dynamic> data) {
    return Umbrella(
      umbrellaId: data['umbrellaId'] ?? '',
      resistance: (data['resistance'] as num?)?.toDouble() ?? 0.0,
      stationId: data['stationId'],
      status: data['status'] ?? 'available',
      createdAt: (data['createdAt'] is Timestamp)
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }
}
