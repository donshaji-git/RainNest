import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/models/user_model.dart';
import '../data/models/station.dart';
import '../data/models/umbrella.dart';
import '../data/models/transaction.dart';

class DatabaseService {
  DatabaseService();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Collection References
  CollectionReference get _usersCollection => _db.collection('users');
  CollectionReference get _stationsCollection => _db.collection('stations');
  CollectionReference get _umbrellasCollection => _db.collection('umbrellas');
  CollectionReference get _transactionsCollection =>
      _db.collection('transactions');

  // --- User Methods ---

  Future<bool> userExists(String uid) async {
    final doc = await _usersCollection.doc(uid).get();
    return doc.exists;
  }

  Future<void> saveUser(UserModel user) async {
    await _usersCollection.doc(user.uid).set(user.toMap());
  }

  Future<UserModel?> getUser(String uid) async {
    DocumentSnapshot doc = await _usersCollection.doc(uid).get();
    if (doc.exists) {
      return UserModel.fromMap(doc.data() as Map<String, dynamic>);
    }
    return null;
  }

  Stream<UserModel?> getUserStream(String uid) {
    return _usersCollection.doc(uid).snapshots().map((doc) {
      if (doc.exists) {
        return UserModel.fromMap(doc.data() as Map<String, dynamic>);
      }
      return null;
    });
  }

  // --- Station Methods ---

  Stream<List<Station>> getStationsStream() {
    return _stationsCollection.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return Station.fromMap(doc.data() as Map<String, dynamic>, doc.id);
      }).toList();
    });
  }

  Future<Station?> getStation(String stationId) async {
    DocumentSnapshot doc = await _stationsCollection.doc(stationId).get();
    if (doc.exists) {
      return Station.fromMap(doc.data() as Map<String, dynamic>, doc.id);
    }
    return null;
  }

  // --- Umbrella Methods ---

  Future<Umbrella?> getUmbrella(String umbrellaId) async {
    DocumentSnapshot doc = await _umbrellasCollection.doc(umbrellaId).get();
    if (doc.exists) {
      return Umbrella.fromMap(doc.data() as Map<String, dynamic>);
    }
    return null;
  }

  // --- Rental Flow (FIFO) ---

  Future<double> getRequiredPayment(String userId) async {
    final userSnap = await _usersCollection.doc(userId).get();
    if (!userSnap.exists) return 110.0;
    final user = UserModel.fromMap(userSnap.data() as Map<String, dynamic>);

    // Unified: We want walletBalance to be at least 100
    double currentBalance = user.walletBalance;
    double topupNeeded = (100.0 - currentBalance).clamp(0.0, 100.0);
    return topupNeeded + 10.0; // Topup + Rental Fee
  }

  Future<Map<String, dynamic>> rentUmbrella({
    required String stationId,
    required String userId,
    String? paymentId,
    String? orderId,
    String? signature,
    Map<String, dynamic>? paymentLog,
    double addedBalance = 0.0,
  }) async {
    return await _db.runTransaction((transaction) async {
      // 1. Get User
      DocumentReference userRef = _usersCollection.doc(userId);
      DocumentSnapshot userSnap = await transaction.get(userRef);
      if (!userSnap.exists) throw Exception("User not found");

      UserModel user = UserModel.fromMap(
        userSnap.data() as Map<String, dynamic>,
      );

      // Business Logic: Unified Balance
      double topupNeeded = (100.0 - user.walletBalance).clamp(0.0, 100.0);
      double totalRequired = topupNeeded + 10.0;

      double finalWalletBalance = user.walletBalance;

      if (addedBalance > 0) {
        // Razorpay payment
        if (addedBalance < totalRequired) {
          throw Exception("Payment insufficient. Required: ₹$totalRequired");
        }
        finalWalletBalance +=
            addedBalance - 10.0; // Add deposit/topup, subtract rent
      } else {
        // Wallet payment
        if (finalWalletBalance < totalRequired) {
          throw Exception("Insufficient balance for ₹$totalRequired");
        }
        finalWalletBalance -=
            10.0; // Only subtract rent if topup was already in wallet
      }

      // Max 3 umbrellas at a time
      if (user.activeRentalIds.length >= 3) {
        throw Exception("You can rent a maximum of 3 umbrellas at a time.");
      }

      // 2. Get Station
      DocumentReference stationRef = _stationsCollection.doc(stationId);
      DocumentSnapshot stationSnap = await transaction.get(stationRef);
      if (!stationSnap.exists) throw Exception("Station not found");

      Station station = Station.fromMap(
        stationSnap.data() as Map<String, dynamic>,
        stationSnap.id,
      );

      if (station.queueOrder.isEmpty) throw Exception("No umbrellas available");

      // 3. FIFO: Get first umbrella ID
      String umbrellaId = station.queueOrder.first;
      List<String> newQueue = List<String>.from(station.queueOrder)
        ..removeAt(0);

      // 4. Update Station
      transaction.update(stationRef, {
        'queueOrder': newQueue,
        'availableCount': FieldValue.increment(-1),
        'freeSlotsCount': FieldValue.increment(1),
      });

      // 5. Update Umbrella
      DocumentReference umbrellaRef = _umbrellasCollection.doc(umbrellaId);
      transaction.update(umbrellaRef, {'status': 'rented', 'stationId': null});

      transaction.update(userRef, {
        'activeRentalIds': FieldValue.arrayUnion([umbrellaId]),
        'walletBalance': finalWalletBalance,
        'securityDeposit': finalWalletBalance.clamp(
          0.0,
          100.0,
        ), // Keep for backward compat
        'hasSecurityDeposit': finalWalletBalance >= 100.0,
      });

      // 7. Record Admin Earnings
      DocumentReference adminRef = _db.collection('admin').doc('stats');
      transaction.set(adminRef, {
        'totalEarnings': FieldValue.increment(10.0),
      }, SetOptions(merge: true));

      // 8. Record Transactions
      DocumentReference rentTransRef = _transactionsCollection.doc();
      TransactionModel rentTx = TransactionModel(
        transactionId: rentTransRef.id,
        userId: userId,
        umbrellaId: umbrellaId,
        paymentId: paymentId,
        orderId: orderId,
        signature: signature,
        paymentLog: paymentLog,
        rentalAmount: 10.0,
        status: 'success',
        type: 'rental_fee',
        timestamp: DateTime.now(),
      );
      transaction.set(rentTransRef, rentTx.toMap());

      if (addedBalance > 10.0 || topupNeeded > 0) {
        double depositAmt = addedBalance > 0
            ? (addedBalance - 10.0)
            : topupNeeded;
        DocumentReference depositTransRef = _transactionsCollection.doc();
        TransactionModel depositTx = TransactionModel(
          transactionId: depositTransRef.id,
          userId: userId,
          paymentId: paymentId,
          orderId: orderId,
          signature: signature,
          paymentLog: paymentLog,
          securityDeposit: depositAmt,
          status: 'success',
          type: 'deposit',
          timestamp: DateTime.now(),
        );
        transaction.set(depositTransRef, depositTx.toMap());
      }

      return {'transactionId': rentTransRef.id, 'umbrellaId': umbrellaId};
    });
  }

  Future<void> requestRedemption(String userId) async {
    final userSnap = await _usersCollection.doc(userId).get();
    if (!userSnap.exists) throw Exception("User not found");
    final user = UserModel.fromMap(userSnap.data() as Map<String, dynamic>);

    if (user.activeRentalIds.isNotEmpty) {
      throw Exception(
        "Please return all umbrellas before requesting a deposit refund.",
      );
    }

    await _usersCollection.doc(userId).update({
      'redemptionStatus': 'pending',
      'redemptionRequestedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> redeemSecurityDeposit(String userId) async {
    await _db.runTransaction((transaction) async {
      DocumentReference userRef = _usersCollection.doc(userId);
      DocumentSnapshot userSnap = await transaction.get(userRef);
      if (!userSnap.exists) throw Exception("User not found");

      UserModel user = UserModel.fromMap(
        userSnap.data() as Map<String, dynamic>,
      );

      if (user.redemptionStatus != 'pending') {
        throw Exception("Redemption not requested or already processed");
      }

      if (user.activeRentalIds.isNotEmpty) {
        throw Exception("Return all umbrellas before redeeming deposit");
      }

      if (user.redemptionRequestedAt != null) {
        final now = DateTime.now();
        final days = now.difference(user.redemptionRequestedAt!).inDays;
        if (days < 5) {
          throw Exception(
            "Deposit can only be redeemed after 5 days of verification",
          );
        }
      } else {
        throw Exception("Redemption request date not found");
      }

      transaction.update(userRef, {
        'hasSecurityDeposit': false,
        'redemptionStatus': 'completed',
        // Wallet balance remains what it is, just marked as redeemed (refunded by admin)
      });

      // Record Refund Transaction
      DocumentReference transRef = _transactionsCollection.doc();
      TransactionModel t = TransactionModel(
        transactionId: transRef.id,
        userId: userId,
        securityDeposit:
            user.walletBalance, // Refund the entire current wallet balance
        status: 'success',
        type: 'refund',
        timestamp: DateTime.now(),
      );
      transaction.set(transRef, t.toMap());
    });
  }

  // --- Return Flow ---

  Future<void> returnUmbrella({
    required String transactionId,
    required String userId,
    required String stationId,
    required String umbrellaId,
  }) async {
    await _db.runTransaction((transaction) async {
      // 1. Get Transaction to find start time
      DocumentReference originalTransRef = _transactionsCollection.doc(
        transactionId,
      );
      DocumentSnapshot originalTransSnap = await transaction.get(
        originalTransRef,
      );
      if (!originalTransSnap.exists) {
        throw Exception("Rental record not found");
      }

      TransactionModel originalTx = TransactionModel.fromMap(
        originalTransSnap.data() as Map<String, dynamic>,
        originalTransSnap.id,
      );

      // Calculate Penalty
      final now = DateTime.now();
      final diff = now.difference(originalTx.timestamp);
      final elapsedHours = diff.inHours;
      double penalty = 0.0;
      if (elapsedHours > 10) {
        penalty = (elapsedHours - 10) * 5.0;
      }

      // 2. Get Station
      DocumentReference stationRef = _stationsCollection.doc(stationId);
      DocumentSnapshot stationSnap = await transaction.get(stationRef);
      if (!stationSnap.exists) throw Exception("Station not found");

      // 3. Update Station (Append to FIFO queue)
      transaction.update(stationRef, {
        'queueOrder': FieldValue.arrayUnion([umbrellaId]),
        'availableCount': FieldValue.increment(1),
        'freeSlotsCount': FieldValue.increment(-1),
      });

      // 4. Update Umbrella
      DocumentReference umbrellaRef = _umbrellasCollection.doc(umbrellaId);
      transaction.update(umbrellaRef, {
        'status': 'available',
        'stationId': stationId,
      });

      // 5. Update User & Settle Penalty
      DocumentReference userRef = _usersCollection.doc(userId);
      DocumentSnapshot userSnap = await transaction.get(userRef);
      if (!userSnap.exists) throw Exception("User not found");
      UserModel user = UserModel.fromMap(
        userSnap.data() as Map<String, dynamic>,
      );
      double finalWalletBalance = user.walletBalance;

      if (penalty > 0) {
        finalWalletBalance -= penalty;
      }

      transaction.update(userRef, {
        'activeRentalIds': FieldValue.arrayRemove([umbrellaId]),
        'walletBalance': finalWalletBalance,
        'securityDeposit': finalWalletBalance.clamp(0.0, 100.0),
        'hasSecurityDeposit': finalWalletBalance >= 100.0,
        // Reset fine accumulated for this specific rental
        'fineAccumulated': 0.0,
      });

      // 6. Record Admin Penalty Earnings
      if (penalty > 0) {
        DocumentReference adminRef = _db.collection('admin').doc('stats');
        transaction.set(adminRef, {
          'totalFineCollected': FieldValue.increment(penalty),
        }, SetOptions(merge: true));

        // 7. Record Penalty Transaction
        DocumentReference penaltyTransRef = _transactionsCollection.doc();
        TransactionModel penaltyTx = TransactionModel(
          transactionId: penaltyTransRef.id,
          userId: userId,
          umbrellaId: umbrellaId,
          penaltyAmount: penalty,
          status: 'success',
          type: 'penalty',
          timestamp: DateTime.now(),
        );
        transaction.set(penaltyTransRef, penaltyTx.toMap());
      }

      // 8. Update original rental transaction
      transaction.update(originalTransRef, {
        'status': 'completed',
        'penaltyAmount': penalty,
        'returnTimestamp': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Syncs fines for all active rentals of a user
  /// Calculated as ₹5/hr after 10hr free period
  Future<void> syncActiveFines(String userId) async {
    final userSnap = await _usersCollection.doc(userId).get();
    if (!userSnap.exists) return;
    UserModel user = UserModel.fromMap(userSnap.data() as Map<String, dynamic>);

    if (user.activeRentalIds.isEmpty) return;

    // Get the most recent rental transactions for these umbrellas
    final rentalsSnap = await _transactionsCollection
        .where('userId', isEqualTo: userId)
        .where('type', isEqualTo: 'rental_fee')
        // Simplified: assuming we can find them. In production,
        // handle multiple active rentals specifically.
        .get();

    double totalNewFine = 0.0;
    final now = DateTime.now();

    for (var doc in rentalsSnap.docs) {
      final tx = TransactionModel.fromMap(
        doc.data() as Map<String, dynamic>,
        doc.id,
      );
      if (user.activeRentalIds.contains(tx.umbrellaId)) {
        final elapsed = now.difference(tx.timestamp).inHours;
        if (elapsed > 10) {
          totalNewFine += (elapsed - 10) * 5.0;
        }
      }
    }

    await _usersCollection.doc(userId).update({
      'fineAccumulated': totalNewFine,
    });
  }

  // --- NodeMCU Integration ---

  Stream<List<TransactionModel>> getActiveRentalsStream(String userId) {
    return _transactionsCollection
        .where('userId', isEqualTo: userId)
        .where('status', isEqualTo: 'success')
        .where('type', isEqualTo: 'rental_fee')
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            return TransactionModel.fromMap(
              doc.data() as Map<String, dynamic>,
              doc.id,
            );
          }).toList();
        });
  }

  Stream<List<TransactionModel>> getTransactionsStream(String userId) {
    return _transactionsCollection
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            return TransactionModel.fromMap(
              doc.data() as Map<String, dynamic>,
              doc.id,
            );
          }).toList();
        });
  }

  Future<void> updateUmbrellaFromHardware({
    required String umbrellaId, // Resistance value
    required String stationId,
    String status = 'available',
  }) async {
    DocumentReference umbrellaRef = _umbrellasCollection.doc(umbrellaId);
    DocumentSnapshot umbrellaSnap = await umbrellaRef.get();

    if (!umbrellaSnap.exists) {
      // Create new umbrella
      Umbrella newUmbrella = Umbrella(
        umbrellaId: umbrellaId,
        stationId: stationId,
        status: status,
        createdAt: DateTime.now(),
      );
      await umbrellaRef.set(newUmbrella.toMap());
    } else {
      // Update existing
      await umbrellaRef.update({'stationId': stationId, 'status': status});
    }
  }

  Future<void> addStation(Station station) async {
    await _stationsCollection.add(station.toMap());
  }

  Future<void> updateStation(Station station) async {
    await _stationsCollection.doc(station.stationId).update(station.toMap());
  }

  Future<void> deleteStation(String stationId) async {
    await _stationsCollection.doc(stationId).delete();
  }

  Future<void> saveUmbrella(Umbrella umbrella) async {
    await _umbrellasCollection.doc(umbrella.umbrellaId).set(umbrella.toMap());
  }

  Future<List<Station>> getAllStations() async {
    final snap = await _stationsCollection.get();
    return snap.docs.map((doc) {
      return Station.fromMap(doc.data() as Map<String, dynamic>, doc.id);
    }).toList();
  }
}
