import 'package:cloud_firestore/cloud_firestore.dart';

class TransactionModel {
  final String transactionId;
  final String userId;
  final String? umbrellaId;
  final String? paymentId; // Razorpay payment ID
  final double rentalAmount;
  final double securityDeposit;
  final double penaltyAmount;
  final String status; // 'success', 'failed', 'pending'
  final String type; // 'payment', 'rental_fee', 'deposit', 'refund', 'penalty'
  final DateTime timestamp;

  TransactionModel({
    required this.transactionId,
    required this.userId,
    this.umbrellaId,
    this.paymentId,
    this.rentalAmount = 0.0,
    this.securityDeposit = 0.0,
    this.penaltyAmount = 0.0,
    required this.status,
    required this.type,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'transactionId': transactionId,
      'userId': userId,
      'umbrellaId': umbrellaId,
      'paymentId': paymentId,
      'rentalAmount': rentalAmount,
      'securityDeposit': securityDeposit,
      'penaltyAmount': penaltyAmount,
      'status': status,
      'type': type,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }

  factory TransactionModel.fromMap(Map<String, dynamic> data, String id) {
    return TransactionModel(
      transactionId: id,
      userId: data['userId'] ?? '',
      umbrellaId: data['umbrellaId'],
      paymentId: data['paymentId'],
      rentalAmount: (data['rentalAmount'] as num?)?.toDouble() ?? 0.0,
      securityDeposit: (data['securityDeposit'] as num?)?.toDouble() ?? 0.0,
      penaltyAmount: (data['penaltyAmount'] as num?)?.toDouble() ?? 0.0,
      status: data['status'] ?? 'pending',
      type: data['type'] ?? 'payment',
      timestamp: (data['timestamp'] is Timestamp)
          ? (data['timestamp'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }
}
