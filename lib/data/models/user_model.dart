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
    };
  }
}
