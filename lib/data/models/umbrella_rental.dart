import 'package:cloud_firestore/cloud_firestore.dart';

class UmbrellaRental {
  final String id;
  final String userId;
  final String umbrellaId;
  final String machineId;
  final String machineName;
  final double machineLat;
  final double machineLon;
  final double userLat;
  final double userLon;
  final DateTime rentalTime;
  final DateTime? returnTime;
  final String? returnSlotId;
  final double rentalFee;
  final double fineAmount;
  final String status; // 'active', 'completed', 'returned_early'

  UmbrellaRental({
    required this.id,
    required this.userId,
    required this.umbrellaId,
    required this.machineId,
    required this.machineName,
    required this.machineLat,
    required this.machineLon,
    required this.userLat,
    required this.userLon,
    required this.rentalTime,
    this.returnTime,
    this.returnSlotId,
    required this.rentalFee,
    this.fineAmount = 0.0,
    required this.status,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'umbrellaId': umbrellaId,
      'machineId': machineId,
      'machineName': machineName,
      'machineLat': machineLat,
      'machineLon': machineLon,
      'userLat': userLat,
      'userLon': userLon,
      'rentalTime': Timestamp.fromDate(rentalTime),
      'returnTime': returnTime != null ? Timestamp.fromDate(returnTime!) : null,
      'returnSlotId': returnSlotId,
      'rentalFee': rentalFee,
      'fineAmount': fineAmount,
      'status': status,
    };
  }

  factory UmbrellaRental.fromMap(Map<String, dynamic> map, String id) {
    return UmbrellaRental(
      id: id,
      userId: map['userId'] ?? '',
      umbrellaId: map['umbrellaId'] ?? '',
      machineId: map['machineId'] ?? '',
      machineName: map['machineName'] ?? '',
      machineLat: (map['machineLat'] as num).toDouble(),
      machineLon: (map['machineLon'] as num).toDouble(),
      userLat: (map['userLat'] as num).toDouble(),
      userLon: (map['userLon'] as num).toDouble(),
      rentalTime: (map['rentalTime'] as Timestamp).toDate(),
      returnTime: map['returnTime'] != null
          ? (map['returnTime'] as Timestamp).toDate()
          : null,
      returnSlotId: map['returnSlotId'],
      rentalFee: (map['rentalFee'] as num).toDouble(),
      fineAmount: (map['fineAmount'] as num).toDouble(),
      status: map['status'] ?? 'active',
    );
  }
}
