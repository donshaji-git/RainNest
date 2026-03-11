import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/models/user_model.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../presentation/constants/admin_constants.dart';

class UserProvider with ChangeNotifier {
  final DatabaseService _db = DatabaseService();
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<UserModel?>? _userSubscription;

  UserModel? _user;
  User? _firebaseUser;
  bool _isLoading = false;

  UserModel? get user => _user;
  User? get firebaseUser => _firebaseUser;
  bool get isLoading => _isLoading;
  bool get hasActiveRentals => _user?.activeRentalIds.isNotEmpty ?? false;

  UserProvider() {
    _initialize();
  }

  void _initialize() {
    // 1. Initial check for existing user
    _firebaseUser = FirebaseAuth.instance.currentUser;
    if (_firebaseUser != null) {
      _listenToUser(_firebaseUser!.uid);
    }

    // 2. Continuous listener for auth changes
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((
      firebaseUser,
    ) {
      _firebaseUser = firebaseUser;
      if (firebaseUser == null) {
        _user = null;
        _userSubscription?.cancel();
        _userSubscription = null;
        _isLoading = false;
        NotificationService()
            .unsubscribeFromAdminAlerts(); // Unsubscribe on logout
        notifyListeners();
      } else {
        // Subscribe to admin topics if they are an admin
        if (AdminConstants.isAdmin(firebaseUser.email ?? '')) {
          NotificationService().subscribeToAdminAlerts();
        }

        // Only start listening if it's a DIFFERENT user or we aren't listening yet
        if (_user == null || _user!.uid != firebaseUser.uid) {
          _listenToUser(firebaseUser.uid);
        } else {
          // Even if we are already listening, we need to notify that firebaseUser is updated
          notifyListeners();
        }
      }
    });
  }

  void _listenToUser(String uid) {
    // If we are already listening to this UID and it's not a fresh login, skip
    if (_userSubscription != null && _user?.uid == uid) return;

    _isLoading = true;
    notifyListeners();
    _userSubscription?.cancel();

    // Safety timeout: If user data doesn't arrive in 3 seconds, stop loading
    // This prevents the "hang" if Firestore is slow or document is missing
    Timer? timeout;
    timeout = Timer(const Duration(seconds: 3), () {
      if (_isLoading) {
        _isLoading = false;
        notifyListeners();
      }
    });

    _userSubscription = _db
        .getUserStream(uid)
        .listen(
          (userData) {
            timeout?.cancel();
            _user = userData;
            _isLoading = false;
            debugPrint(
              "UserProvider: stream emitted data. User is ${_user != null ? 'Found' : 'NULL'}",
            );
            notifyListeners();
          },
          onError: (e) {
            timeout?.cancel();
            _isLoading = false;
            debugPrint("UserProvider: stream error $e");
            notifyListeners();
          },
          cancelOnError: false,
        );
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _userSubscription?.cancel();
    super.dispose();
  }
}
