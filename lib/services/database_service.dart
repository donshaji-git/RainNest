import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart' hide Query;
import '../data/models/user_model.dart';
import '../data/models/station.dart';
import '../data/models/umbrella.dart';
import '../data/models/transaction.dart';

class DatabaseService {
  DatabaseService();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseDatabase _rtdb = FirebaseDatabase.instance;

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

    double fineToClear = user.fineAccumulated;
    // We want the user to have 100 (deposit) + 10 (rent) after paying the fine
    double paymentNeeded = (110.0 + fineToClear - user.walletBalance).clamp(
      0.0,
      1000.0,
    );

    return paymentNeeded;
  }

  Future<Map<String, dynamic>> rentUmbrella({
    required String stationId,
    required String userId,
    String? paymentId,
    String? orderId,
    String? signature,
    Map<String, dynamic>? paymentLog,
    double addedBalance = 0.0,
    double? latitude,
    double? longitude,
  }) async {
    return await _db.runTransaction((transaction) async {
      // 1. Get User
      DocumentReference userRef = _usersCollection.doc(userId);
      DocumentSnapshot userSnap = await transaction.get(userRef);
      if (!userSnap.exists) throw Exception("User not found");

      UserModel user = UserModel.fromMap(
        userSnap.data() as Map<String, dynamic>,
      );

      // Business Logic: Unified Balance to reach 110 (100 deposit + 10 rent) + fines
      double fineToClear = user.fineAccumulated;
      double paymentNeeded = (110.0 + fineToClear - user.walletBalance).clamp(
        0.0,
        1000.0,
      );

      double finalWalletBalance = user.walletBalance;

      if (addedBalance > 0) {
        // Razorpay payment path
        if (addedBalance < paymentNeeded && paymentNeeded > 0) {
          throw Exception("Payment insufficient. Required: ₹$paymentNeeded");
        }
        // Resulting balance = current + added - (rent + fine)
        finalWalletBalance =
            user.walletBalance + addedBalance - 10.0 - fineToClear;
      } else {
        // Wallet payment path
        // Ensure user has at least 110 + fines
        double requiredTotal = 110.0 + fineToClear;
        if (user.walletBalance < requiredTotal) {
          throw Exception(
            "Insufficient balance. Please top up to reach ₹110 after fines.",
          );
        }
        finalWalletBalance = user.walletBalance - 10.0 - fineToClear;
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
        'securityDeposit': finalWalletBalance.clamp(0.0, 100.0),
        'hasSecurityDeposit': finalWalletBalance >= 100.0,
        'fineAccumulated': 0.0,
      });

      // 7. Record Admin Earnings
      DocumentReference adminRef = _db.collection('admin').doc('stats');
      transaction.set(adminRef, {
        'totalEarnings': FieldValue.increment(10.0), // Rent
        'totalFineCollected': FieldValue.increment(fineToClear), // Paid Fines
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
        latitude: latitude,
        longitude: longitude,
        status: 'active',
        type: 'rental_fee',
        timestamp: DateTime.now(),
      );
      transaction.set(rentTransRef, rentTx.toMap());

      if (addedBalance > 0 || fineToClear > 0) {
        // 1. Record the Razorpay payment as a top-up credit (MINUS the rental fee)
        if (addedBalance > 0) {
          double topupAmount = (addedBalance - 10.0).clamp(0.0, 1000.0);
          if (topupAmount > 0) {
            DocumentReference topupTransRef = _transactionsCollection.doc();
            TransactionModel topupTx = TransactionModel(
              transactionId: topupTransRef.id,
              userId: userId,
              paymentId: paymentId,
              orderId: orderId,
              signature: signature,
              paymentLog: paymentLog,
              rentalAmount: topupAmount,
              latitude: latitude,
              longitude: longitude,
              status: 'success',
              type: 'topup',
              timestamp: DateTime.now(),
            );
            transaction.set(topupTransRef, topupTx.toMap());
          }
        }

        // 2. Record fine payment if there was one
        if (fineToClear > 0) {
          DocumentReference finePayRef = _transactionsCollection.doc();
          TransactionModel finePayTx = TransactionModel(
            transactionId: finePayRef.id,
            userId: userId,
            paymentId: paymentId,
            orderId: orderId,
            signature: signature,
            paymentLog: paymentLog,
            penaltyAmount: fineToClear,
            latitude: latitude,
            longitude: longitude,
            status: 'success',
            type: 'penalty_payment',
            timestamp: DateTime.now(),
          );
          transaction.set(finePayRef, finePayTx.toMap());
        }
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
        if (days < 2) {
          throw Exception(
            "Deposit can only be redeemed after 2 days of verification",
          );
        }
      } else {
        throw Exception("Redemption request date not found");
      }

      transaction.update(userRef, {
        'hasSecurityDeposit': false,
        'redemptionStatus': 'completed',
        'walletBalance': 0.0, // Reset balance as it's being refunded
        'securityDeposit': 0.0,
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

  Future<void> cancelRedemption(String userId) async {
    await _usersCollection.doc(userId).update({
      'redemptionStatus': null,
      'redemptionRequestedAt': null,
    });
  }

  // --- Return Flow ---

  Future<Map<String, dynamic>> processFullReturn({
    required String transactionId,
    required String userId,
    required String stationId,
    required String umbrellaId,
    bool isDamaged = false,
    String? damageType,
  }) async {
    return await _db.runTransaction((transaction) async {
      // 1. Get Rental Transaction
      DocumentReference originalTransRef = _transactionsCollection.doc(
        transactionId,
      );
      DocumentSnapshot originalTransSnap = await transaction.get(
        originalTransRef,
      );
      if (!originalTransSnap.exists) throw Exception("Rental record not found");

      TransactionModel originalTx = TransactionModel.fromMap(
        originalTransSnap.data() as Map<String, dynamic>,
        originalTransSnap.id,
      );

      if (originalTx.status == 'success') {
        throw Exception("Rental already returned");
      }

      // 2. Calculate Penalty (Server-side time using current session)
      final now = DateTime.now();
      final diff = now.difference(originalTx.timestamp);
      final totalMinutes = diff.inMinutes;
      double penalty = 0.0;
      if (totalMinutes > 600) {
        int overdueHours = (totalMinutes / 60.0).ceil() - 10;
        penalty = overdueHours * 5.0;
      }

      // 3. Get User
      DocumentReference userRef = _usersCollection.doc(userId);
      DocumentSnapshot userSnap = await transaction.get(userRef);
      if (!userSnap.exists) throw Exception("User not found");
      UserModel user = UserModel.fromMap(
        userSnap.data() as Map<String, dynamic>,
      );

      // Verify user has this active rental
      if (!user.activeRentalIds.contains(umbrellaId)) {
        throw Exception("Umbrella not found in active rentals");
      }

      // 4. Update Station (Append to end of queueOrder array)
      DocumentReference stationRef = _stationsCollection.doc(stationId);
      DocumentSnapshot stationSnap = await transaction.get(stationRef);
      if (!stationSnap.exists) throw Exception("Station not found");

      Station station = Station.fromMap(
        stationSnap.data() as Map<String, dynamic>,
        stationSnap.id,
      );

      // Atomic append using FieldValue.arrayUnion (only work if not exists,
      // but in transaction we can safely build the list)
      List<String> newQueue = List<String>.from(station.queueOrder);
      if (!newQueue.contains(umbrellaId)) {
        newQueue.add(umbrellaId);
      }

      // 5. Update All Docs
      double newWalletBalance = (user.walletBalance - penalty).clamp(
        0.0,
        1000.0,
      );
      double remainingFine = (penalty - user.walletBalance).clamp(0.0, 1000.0);

      transaction.update(stationRef, {
        'queueOrder': newQueue,
        'availableCount': FieldValue.increment(1),
        'freeSlotsCount': FieldValue.increment(-1),
      });

      transaction.update(userRef, {
        'activeRentalIds': FieldValue.arrayRemove([umbrellaId]),
        'walletBalance': newWalletBalance,
        'coins': FieldValue.increment(penalty == 0 ? 10 : 0),
        'securityDeposit': newWalletBalance.clamp(0.0, 100.0),
        'hasSecurityDeposit': newWalletBalance >= 100.0,
        'fineAccumulated': remainingFine,
      });

      DocumentReference umbrellaRef = _umbrellasCollection.doc(umbrellaId);
      transaction.update(umbrellaRef, {
        'status': isDamaged ? 'damaged' : 'available',
        'stationId': stationId,
        'lastDamageReport': isDamaged ? damageType : null,
      });

      transaction.update(originalTransRef, {
        'status': 'success',
        'penaltyAmount': penalty,
        'returnTimestamp': FieldValue.serverTimestamp(),
        'condition': isDamaged ? 'damaged' : 'ok',
      });

      // Record penalty transaction for history if fine exists
      if (penalty > 0) {
        DocumentReference penaltyTxRef = _transactionsCollection.doc();
        TransactionModel penaltyTx = TransactionModel(
          transactionId: penaltyTxRef.id,
          userId: userId,
          umbrellaId: umbrellaId,
          penaltyAmount: penalty,
          status: 'success',
          type: 'penalty',
          timestamp: DateTime.now(),
        );
        transaction.set(penaltyTxRef, penaltyTx.toMap());
      }

      // 6. Record Coin Reward Transaction
      if (penalty == 0) {
        DocumentReference coinTxRef = _transactionsCollection.doc();
        TransactionModel coinTx = TransactionModel(
          transactionId: coinTxRef.id,
          userId: userId,
          umbrellaId: umbrellaId,
          coins: 10,
          status: 'success',
          type: 'coin_reward',
          timestamp: DateTime.now(),
        );
        transaction.set(coinTxRef, coinTx.toMap());
      }

      // 7. Record Damage Report for Admin if applicable
      if (isDamaged) {
        DocumentReference damageRef = _db.collection('damage_reports').doc();
        transaction.set(damageRef, {
          'reportId': damageRef.id,
          'umbrellaId': umbrellaId,
          'userId': userId,
          'type': damageType,
          'timestamp': FieldValue.serverTimestamp(),
          'status': 'pending_review',
        });
      }

      // 7. Record Penalty Transaction if any
      if (penalty > 0) {
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

        DocumentReference adminRef = _db.collection('admin').doc('stats');
        transaction.set(adminRef, {
          'totalFineCollected': FieldValue.increment(penalty),
        }, SetOptions(merge: true));
      }

      // 8. Record Return Transaction (Success Record)
      DocumentReference returnTransRef = _transactionsCollection.doc();
      TransactionModel returnTx = TransactionModel(
        transactionId: returnTransRef.id,
        userId: userId,
        umbrellaId: umbrellaId,
        rentalAmount: 0.0,
        status: 'success',
        type: 'return',
        timestamp: DateTime.now(),
      );
      transaction.set(returnTransRef, returnTx.toMap());

      return {'penalty': penalty, 'duration': diff.inMinutes, 'timestamp': now};
    });
  }

  // Backward compatibility wrapper for old return flow
  Future<void> returnUmbrella({
    required String transactionId,
    required String userId,
    required String stationId,
    required String umbrellaId,
  }) async {
    await processFullReturn(
      transactionId: transactionId,
      userId: userId,
      stationId: stationId,
      umbrellaId: umbrellaId,
    );
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
        // We filter status in-memory to avoid requiring a composite index
        .get();

    double totalNewFine = 0.0;
    final now = DateTime.now();

    for (var doc in rentalsSnap.docs) {
      final tx = TransactionModel.fromMap(
        doc.data() as Map<String, dynamic>,
        doc.id,
      );
      if (user.activeRentalIds.contains(tx.umbrellaId) &&
          (tx.status == 'active' || tx.status == 'late')) {
        final totalMinutes = now.difference(tx.timestamp).inMinutes;
        bool isLate = false;
        if (totalMinutes > 600) {
          int overdueHours = (totalMinutes / 60.0).ceil() - 10;
          totalNewFine += overdueHours * 5.0;
          isLate = true;
        }

        // Update transaction status to 'late' if it's overdue
        if (isLate && tx.status == 'active') {
          await _transactionsCollection.doc(tx.transactionId).update({
            'status': 'late',
          });
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
        .where('type', isEqualTo: 'rental_fee')
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map(
                (doc) => TransactionModel.fromMap(
                  doc.data() as Map<String, dynamic>,
                  doc.id,
                ),
              )
              .where((tx) => tx.status == 'active' || tx.status == 'late')
              .toList();
        });
  }

  Stream<List<TransactionModel>> getTransactionsStream(String userId) {
    return _transactionsCollection
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
          final list = snapshot.docs.map((doc) {
            return TransactionModel.fromMap(
              doc.data() as Map<String, dynamic>,
              doc.id,
            );
          }).toList();
          // Sort in-memory to avoid requiring a composite index
          list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          return list;
        });
  }

  Future<List<TransactionModel>> getUserTransactions(String userId) async {
    final snapshot = await _transactionsCollection
        .where('userId', isEqualTo: userId)
        .get();

    final list = snapshot.docs.map((doc) {
      return TransactionModel.fromMap(
        doc.data() as Map<String, dynamic>,
        doc.id,
      );
    }).toList();

    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
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
        resistance: double.tryParse(umbrellaId) ?? 0.0,
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

  Future<bool> isQrCodeUnique(String qrCode, {String? excludeStationId}) async {
    Query query = _stationsCollection.where('machineQrCode', isEqualTo: qrCode);
    final snapshot = await query.get();

    if (excludeStationId != null) {
      return snapshot.docs.where((doc) => doc.id != excludeStationId).isEmpty;
    }
    return snapshot.docs.isEmpty;
  }

  Future<DocumentReference> addStation(Station station) async {
    return await _stationsCollection.add(station.toMap());
  }

  Future<void> updateStation(Station station) async {
    await _stationsCollection.doc(station.stationId).update(station.toMap());
  }

  Future<void> deleteStation(String stationId) async {
    await _stationsCollection.doc(stationId).delete();
  }

  Future<void> saveUmbrella(Umbrella umbrella) async {
    // 1. Write to Firestore
    await _umbrellasCollection.doc(umbrella.umbrellaId).set(umbrella.toMap());

    // 2. Write Resistance to RTDB for NodeMCU (Registry)
    await _rtdb.ref('umbrella_registry/${umbrella.umbrellaId}').set({
      'id': umbrella.umbrellaId,
      'res': umbrella.resistance,
    });
  }

  Future<List<Station>> getAllStations() async {
    final snap = await _stationsCollection.get();
    return snap.docs.map((doc) {
      return Station.fromMap(doc.data() as Map<String, dynamic>, doc.id);
    }).toList();
  }

  Future<Map<int, Map<String, double>>> getMonthlyRentalStats(
    int month,
    int year,
  ) async {
    final start = DateTime(year, month, 1);
    final nextMonth = month == 12 ? 1 : month + 1;
    final nextYear = month == 12 ? year + 1 : year;
    final end = DateTime(nextYear, nextMonth, 1);

    final snapshot = await _transactionsCollection
        .where('timestamp', isGreaterThanOrEqualTo: start)
        .where('timestamp', isLessThan: end)
        .get();

    // Map to store daily totals: {day: {'revenue': 0.0, 'fines': 0.0, 'security': 0.0}}
    Map<int, Map<String, double>> dailyStats = {};

    for (var doc in snapshot.docs) {
      final tx = TransactionModel.fromMap(
        doc.data() as Map<String, dynamic>,
        doc.id,
      );

      final day = tx.timestamp.day;
      if (!dailyStats.containsKey(day)) {
        dailyStats[day] = {'revenue': 0.0, 'fines': 0.0, 'security': 0.0};
      }

      if (tx.type == 'rental_fee') {
        dailyStats[day]!['revenue'] =
            (dailyStats[day]!['revenue'] ?? 0.0) + tx.rentalAmount;
      } else if (tx.type == 'penalty_payment' || tx.type == 'penalty') {
        // penalty_payment is the actual collection, penalty is the record
        dailyStats[day]!['fines'] =
            (dailyStats[day]!['fines'] ?? 0.0) +
            (tx.penaltyAmount > 0 ? tx.penaltyAmount : 0);
      } else if (tx.type == 'topup') {
        // Security is the amount added to wallet (deposit)
        dailyStats[day]!['security'] =
            (dailyStats[day]!['security'] ?? 0.0) + tx.rentalAmount;
      }
    }

    return dailyStats;
  }
}
