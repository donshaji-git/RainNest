import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/models/user_model.dart';
import '../data/models/station.dart';
import '../data/models/umbrella.dart';
import '../data/models/transaction.dart';

class DatabaseService {
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

  Future<String> rentUmbrella({
    required String stationId,
    required String userId,
    required String paymentId,
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

      // Calculate logic with added balance
      double currentWallet = user.walletBalance + addedBalance;

      // We expect the wallet to have at least 110 (100 security + 10 rent) for the first time
      // or at least 100 + 10 for subsequent times if we want to maintain the 100 balance.
      if (currentWallet < 10.0) {
        throw Exception("Insufficient balance for rental fee.");
      }

      // After 10 Rs deduction, wallet must have at least 100 Rs
      if (currentWallet - 10.0 < 100.0) {
        throw Exception("Insufficient security deposit. 100 Rs required.");
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

      // 6. Update User (Wallet & Active Rentals)
      transaction.update(userRef, {
        'activeRentalIds': FieldValue.arrayUnion([umbrellaId]),
        'walletBalance':
            currentWallet - 10.0, // Deduct 10 Rs, include addedBalance
        'hasSecurityDeposit': true, // User now has security deposit in wallet
      });

      // 7. Record Transaction (Rental Fee)
      DocumentReference transRef = _transactionsCollection.doc();
      TransactionModel t = TransactionModel(
        transactionId: transRef.id,
        userId: userId,
        umbrellaId: umbrellaId,
        paymentId: paymentId,
        rentalAmount: 10.0,
        securityDeposit: addedBalance, // Record if any deposit was added
        status: 'success',
        type: 'rental_fee',
        timestamp: DateTime.now(),
      );
      transaction.set(transRef, t.toMap());

      return transRef.id;
    });
  }

  Future<void> paySecurityDeposit({
    required String userId,
    required String paymentId,
  }) async {
    await _db.runTransaction((transaction) async {
      DocumentReference userRef = _usersCollection.doc(userId);
      DocumentSnapshot userSnap = await transaction.get(userRef);
      if (!userSnap.exists) throw Exception("User not found");

      transaction.update(userRef, {
        'hasSecurityDeposit': true,
        'securityDepositDate': FieldValue.serverTimestamp(),
      });

      // Record Deposit Transaction
      DocumentReference transRef = _transactionsCollection.doc();
      TransactionModel t = TransactionModel(
        transactionId: transRef.id,
        userId: userId,
        paymentId: paymentId,
        securityDeposit: 100.0,
        status: 'success',
        type: 'deposit',
        timestamp: DateTime.now(),
      );
      transaction.set(transRef, t.toMap());
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

      if (!user.hasSecurityDeposit) {
        throw Exception("No security deposit found");
      }
      if (user.activeRentalIds.isNotEmpty) {
        throw Exception("Return all umbrellas before redeeming deposit");
      }

      if (user.securityDepositDate != null) {
        final now = DateTime.now();
        final days = now.difference(user.securityDepositDate!).inDays;
        if (days < 5) {
          throw Exception("Deposit can only be redeemed after 5 days");
        }
      }

      transaction.update(userRef, {
        'hasSecurityDeposit': false,
        'securityDepositDate': null,
        'walletBalance': FieldValue.increment(100.0),
      });

      // Record Refund Transaction
      DocumentReference transRef = _transactionsCollection.doc();
      TransactionModel t = TransactionModel(
        transactionId: transRef.id,
        userId: userId,
        securityDeposit: 100.0,
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

      // 5. Update User (Wallet & Active Rentals)
      DocumentReference userRef = _usersCollection.doc(userId);
      transaction.update(userRef, {
        'activeRentalIds': FieldValue.arrayRemove([umbrellaId]),
        'walletBalance': FieldValue.increment(-penalty),
      });

      // 6. Record Penalty Transaction if any
      if (penalty > 0) {
        DocumentReference penaltyTransRef = _transactionsCollection.doc();
        TransactionModel penaltyT = TransactionModel(
          transactionId: penaltyTransRef.id,
          userId: userId,
          umbrellaId: umbrellaId,
          rentalAmount: penalty,
          status: 'success',
          type: 'penalty',
          timestamp: now,
        );
        transaction.set(penaltyTransRef, penaltyT.toMap());
      }

      // 7. Update original rental transaction
      transaction.update(originalTransRef, {
        'status': 'completed',
        'returnTimestamp': Timestamp.fromDate(now),
        'penaltyAmount': penalty,
      });
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
}
