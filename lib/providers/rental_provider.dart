import 'package:flutter/foundation.dart';
import '../data/models/station.dart';

class RentalProvider with ChangeNotifier {
  Station? _targetStation;
  bool _isVerifying = false;

  Station? get targetStation => _targetStation;
  bool get isVerifying => _isVerifying;

  void setTargetStation(Station? station) {
    _targetStation = station;
    _isVerifying = station != null;
    notifyListeners();
  }

  void clearVerification() {
    _targetStation = null;
    _isVerifying = false;
    notifyListeners();
  }
}
