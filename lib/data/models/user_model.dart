import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String phoneNumber;
  final String countryCode;
  final String name;
  final String surname;
  final String address;
  final String pinCode;
  final String email;
  final bool isEmailVerified;
  final DateTime createdAt;
  final double walletBalance;
  final bool isRented;
  final String? activeRentalId;
  final double totalFines;

  UserModel({
    required this.uid,
    required this.phoneNumber,
    required this.countryCode,
    required this.name,
    required this.surname,
    required this.address,
    required this.pinCode,
    required this.email,
    required this.isEmailVerified,
    required this.createdAt,
    this.walletBalance = 0.0,
    this.isRented = false,
    this.activeRentalId,
    this.totalFines = 0.0,
  });

  factory UserModel.fromMap(Map<String, dynamic> data) {
    return UserModel(
      uid: data['uid'] ?? '',
      phoneNumber: data['phoneNumber'] ?? '',
      countryCode: data['countryCode'] ?? '',
      name: data['name'] ?? '',
      surname: data['surname'] ?? '',
      address: data['address'] ?? '',
      pinCode: data['pinCode'] ?? '',
      email: data['email'] ?? '',
      isEmailVerified: data['isEmailVerified'] ?? false,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      walletBalance: (data['walletBalance'] as num?)?.toDouble() ?? 0.0,
      isRented: data['isRented'] ?? false,
      activeRentalId: data['activeRentalId'],
      totalFines: (data['totalFines'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'phoneNumber': phoneNumber,
      'countryCode': countryCode,
      'name': name,
      'surname': surname,
      'address': address,
      'pinCode': pinCode,
      'email': email,
      'isEmailVerified': isEmailVerified,
      'createdAt': Timestamp.fromDate(createdAt),
      'walletBalance': walletBalance,
      'isRented': isRented,
      'activeRentalId': activeRentalId,
      'totalFines': totalFines,
    };
  }
}
