import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/models/user_model.dart';
import '../services/database_service.dart';

class UserProvider with ChangeNotifier {
  final DatabaseService _db = DatabaseService();
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<UserModel?>? _userSubscription;

  UserModel? _user;
  bool _isLoading = true;

  UserModel? get user => _user;
  bool get isLoading => _isLoading;
  bool get hasActiveRentals => _user?.activeRentalIds.isNotEmpty ?? false;

  UserProvider() {
    _initialize();
  }

  void _initialize() {
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((
      firebaseUser,
    ) {
      if (firebaseUser == null) {
        _user = null;
        _userSubscription?.cancel();
        _isLoading = false;
        notifyListeners();
      } else {
        _listenToUser(firebaseUser.uid);
      }
    });
  }

  void _listenToUser(String uid) {
    _userSubscription?.cancel();
    _userSubscription = _db.getUserStream(uid).listen((userData) {
      _user = userData;
      _isLoading = false;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _userSubscription?.cancel();
    super.dispose();
  }
}
