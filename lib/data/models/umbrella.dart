import 'package:cloud_firestore/cloud_firestore.dart';

class Umbrella {
  final String id; // QR Code value
  final String? currentMachineId;
  final String? currentSlotId;
  final String status; // 'available', 'rented', 'damaged'
  final String? lastUserId;
  final DateTime updatedAt;

  Umbrella({
    required this.id,
    this.currentMachineId,
    this.currentSlotId,
    required this.status,
    this.lastUserId,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'currentMachineId': currentMachineId,
      'currentSlotId': currentSlotId,
      'status': status,
      'lastUserId': lastUserId,
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  factory Umbrella.fromMap(Map<String, dynamic> map) {
    return Umbrella(
      id: map['id'] ?? '',
      currentMachineId: map['currentMachineId'],
      currentSlotId: map['currentSlotId'],
      status: map['status'] ?? 'available',
      lastUserId: map['lastUserId'],
      updatedAt: (map['updatedAt'] as Timestamp).toDate(),
    );
  }
}
