import 'package:cloud_firestore/cloud_firestore.dart';

class Payment {
  final String id;
  final String userId;
  final double amount;
  final String type; // 'SecurityFee', 'RentalFee', 'FineRestoration'
  final DateTime timestamp;
  final String status; // 'success', 'failed'

  Payment({
    required this.id,
    required this.userId,
    required this.amount,
    required this.type,
    required this.timestamp,
    required this.status,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'amount': amount,
      'type': type,
      'timestamp': Timestamp.fromDate(timestamp),
      'status': status,
    };
  }

  factory Payment.fromMap(Map<String, dynamic> map, String id) {
    return Payment(
      id: id,
      userId: map['userId'] ?? '',
      amount: (map['amount'] as num).toDouble(),
      type: map['type'] ?? 'RentalFee',
      timestamp: (map['timestamp'] as Timestamp).toDate(),
      status: map['status'] ?? 'success',
    );
  }
}
