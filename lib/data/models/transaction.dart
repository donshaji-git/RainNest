import 'package:cloud_firestore/cloud_firestore.dart';

class TransactionModel {
  final String transactionId;
  final String userId;
  final String? umbrellaId;
  final String? paymentId; // Razorpay payment ID
  final String? orderId; // Razorpay order ID
  final String? signature; // Razorpay signature
  final Map<String, dynamic>? paymentLog; // Full Razorpay log
  final double rentalAmount;
  final double securityDeposit;
  final double penaltyAmount;
  final int? coins;
  final double? latitude;
  final double? longitude;
  final String status; // 'success', 'failed', 'pending'
  final String type; // 'payment', 'rental_fee', 'deposit', 'refund', 'penalty', 'coin_reward'
  final String? description;
  final DateTime timestamp;

  TransactionModel({
    required this.transactionId,
    required this.userId,
    this.umbrellaId,
    this.paymentId,
    this.orderId,
    this.signature,
    this.paymentLog,
    this.rentalAmount = 0.0,
    this.securityDeposit = 0.0,
    this.penaltyAmount = 0.0,
    this.coins,
    this.latitude,
    this.longitude,
    required this.status,
    required this.type,
    this.description,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'transactionId': transactionId,
      'userId': userId,
      'umbrellaId': umbrellaId,
      'paymentId': paymentId,
      'orderId': orderId,
      'signature': signature,
      'paymentLog': paymentLog,
      'rentalAmount': rentalAmount,
      'securityDeposit': securityDeposit,
      'penaltyAmount': penaltyAmount,
      'coins': coins,
      'latitude': latitude,
      'longitude': longitude,
      'status': status,
      'type': type,
      'description': description,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }

  factory TransactionModel.fromMap(Map<String, dynamic> data, String id) {
    return TransactionModel(
      transactionId: id,
      userId: data['userId'] ?? '',
      umbrellaId: data['umbrellaId'],
      paymentId: data['paymentId'],
      orderId: data['orderId'],
      signature: data['signature'],
      paymentLog: data['paymentLog'] != null
          ? Map<String, dynamic>.from(data['paymentLog'])
          : null,
      rentalAmount: (data['rentalAmount'] as num?)?.toDouble() ?? 0.0,
      securityDeposit: (data['securityDeposit'] as num?)?.toDouble() ?? 0.0,
      penaltyAmount: (data['penaltyAmount'] as num?)?.toDouble() ?? 0.0,
      coins: data['coins'] as int?,
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      status: data['status'] ?? 'pending',
      type: data['type'] ?? 'payment',
      description: data['description'],
      timestamp: (data['timestamp'] is Timestamp)
          ? (data['timestamp'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }
}
