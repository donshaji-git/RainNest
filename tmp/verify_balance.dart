import 'package:flutter/foundation.dart';

// Mocking Timestamp and FieldValue for verification
class Timestamp {
  static DateTime fromDate(DateTime date) => date;
}

class UserModel {
  final double walletBalance;
  final double fineAccumulated;

  UserModel({this.walletBalance = 0.0, this.fineAccumulated = 0.0});

  double get totalBalance =>
      (walletBalance - fineAccumulated).clamp(0.0, 100.0);
}

void main() {
  debugPrint('Testing UserModel.totalBalance clamping logic:');

  final cases = [
    {'wallet': 120.0, 'fine': 0.0, 'expected': 100.0, 'desc': 'Above 100'},
    {
      'wallet': 50.0,
      'fine': 0.0,
      'expected': 50.0,
      'desc': 'Between 0 and 100',
    },
    {
      'wallet': 100.0,
      'fine': 20.0,
      'expected': 80.0,
      'desc': 'Within range after fine',
    },
    {
      'wallet': 10.0,
      'fine': 20.0,
      'expected': 0.0,
      'desc': 'Below 0 after fine',
    },
    {'wallet': 0.0, 'fine': 0.0, 'expected': 0.0, 'desc': 'Exactly 0'},
    {
      'wallet': 200.0,
      'fine': 50.0,
      'expected': 100.0,
      'desc': 'Still above 100 after fine',
    },
    {
      'wallet': 200.0,
      'fine': 150.0,
      'expected': 50.0,
      'desc': 'Drops below 100 after large fine',
    },
  ];

  bool allPassed = true;
  for (var c in cases) {
    final user = UserModel(
      walletBalance: c['wallet'] as double,
      fineAccumulated: c['fine'] as double,
    );
    final result = user.totalBalance;
    final passed = result == c['expected'];
    debugPrint(
      '[${passed ? "PASS" : "FAIL"}] ${c['desc']}: Wallet=${c['wallet']}, Fine=${c['fine']} => Result=$result (Expected=${c['expected']})',
    );
    if (!passed) allPassed = false;
  }

  if (allPassed) {
    debugPrint('\nAll tests passed successfully!');
  } else {
    debugPrint('\nSome tests failed.');
  }
}
