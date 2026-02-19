import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String name;
  final String email;
  final String phoneNumber;
  final double walletBalance;
  final String address;
  final String pinCode;
  final bool hasSecurityDeposit;
  final DateTime? securityDepositDate;
  final List<String> activeRentalIds; // Support multiple rentals
  final DateTime createdAt;

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.phoneNumber,
    this.address = '',
    this.pinCode = '',
    this.walletBalance = 0.0,
    this.hasSecurityDeposit = false,
    this.securityDepositDate,
    this.activeRentalIds = const [],
    required this.createdAt,
  });

  factory UserModel.fromMap(Map<String, dynamic> data) {
    return UserModel(
      uid: data['uid'] ?? '',
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      phoneNumber: data['phoneNumber'] ?? '',
      walletBalance: (data['walletBalance'] as num?)?.toDouble() ?? 0.0,
      hasSecurityDeposit: data['hasSecurityDeposit'] ?? false,
      securityDepositDate: (data['securityDepositDate'] is Timestamp)
          ? (data['securityDepositDate'] as Timestamp).toDate()
          : null,
      address: data['address'] ?? '',
      pinCode: data['pinCode'] ?? '',
      activeRentalIds: List<String>.from(data['activeRentalIds'] ?? []),
      createdAt: (data['createdAt'] is Timestamp)
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'phoneNumber': phoneNumber,
      'walletBalance': walletBalance,
      'hasSecurityDeposit': hasSecurityDeposit,
      'securityDepositDate': securityDepositDate != null
          ? Timestamp.fromDate(securityDepositDate!)
          : null,
      'address': address,
      'pinCode': pinCode,
      'activeRentalIds': activeRentalIds,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
