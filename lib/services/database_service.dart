import 'package:flutter/foundation.dart';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:firebase_database/firebase_database.dart' hide Query;
import '../data/models/user_model.dart';
import '../data/models/station.dart';
import '../data/models/umbrella.dart';
import '../data/models/transaction.dart';
import 'mqtt_service.dart';

class DatabaseService {
  DatabaseService();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseDatabase _rtdb = FirebaseDatabase.instance;
  final MqttService _mqtt = MqttService();
  
  // Collection References
  CollectionReference get _usersCollection => _db.collection('users');
  CollectionReference get _stationsCollection => _db.collection('stations');
  CollectionReference get _umbrellasCollection => _db.collection('umbrellas');
  CollectionReference get _transactionsCollection =>
      _db.collection('transactions');

  // --- User Methods ---

  Future<bool> userExists(String uid) async {
    try {
      final doc = await _usersCollection.doc(uid).get();
      return doc.exists;
    } catch (e) {
      debugPrint("Error checking user existence: $e");
      return false;
    }
  }

  Future<void> saveUser(UserModel user) async {
    try {
      await _usersCollection.doc(user.uid).set(user.toMap());
    } catch (e) {
      debugPrint("Error saving user: $e");
      rethrow;
    }
  }

  Future<UserModel?> getUser(String uid) async {
    try {
      DocumentSnapshot doc = await _usersCollection.doc(uid).get();
      if (doc.exists) {
        return UserModel.fromMap(doc.data() as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint("Error getting user: $e");
    }
    return null;
  }

  Stream<UserModel?> getUserStream(String uid) {
    return _usersCollection.doc(uid).snapshots().map((doc) {
      try {
        if (doc.exists) {
          return UserModel.fromMap(doc.data() as Map<String, dynamic>);
        }
      } catch (e) {
        debugPrint("Error in user stream: $e");
      }
      return null;
    });
  }

  // --- Station Methods ---

  Stream<List<Station>> getStationsStream() {
    return _stationsCollection.snapshots().map((snapshot) {
      try {
        return snapshot.docs.map((doc) {
          return Station.fromMap(doc.data() as Map<String, dynamic>, doc.id);
        }).toList();
      } catch (e) {
        debugPrint("Error in stations stream: $e");
        return [];
      }
    });
  }

  Future<Station?> getStation(String stationId) async {
    try {
      DocumentSnapshot doc = await _stationsCollection.doc(stationId).get();
      if (doc.exists) {
        return Station.fromMap(doc.data() as Map<String, dynamic>, doc.id);
      }
    } catch (e) {
      debugPrint("Error getting station: $e");
    }
    return null;
  }

  // --- Umbrella Methods ---

  Future<Umbrella?> getUmbrella(String umbrellaId) async {
    try {
      DocumentSnapshot doc = await _umbrellasCollection.doc(umbrellaId).get();
      if (doc.exists) {
        return Umbrella.fromMap(doc.data() as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint("Error getting umbrella: $e");
    }
    return null;
  }

  // --- Umbrella Methods ---

  Future<void> sendWaitingCommandToStation(String stationId) async {
    try {
      String path = 'stations/$stationId';
      await _rtdb.ref(path).update({
        'command': 'waiting',
        'timestamp': ServerValue.timestamp,
      }).timeout(const Duration(seconds: 5));
      debugPrint("Waiting command sent to station: $stationId at path: $path");
      
      // Send via MQTT
      _mqtt.publish('rainnest/$stationId/command', 'waiting');
    } catch (e) {
      debugPrint("Error sending waiting command to RTDB: $e");
    }
  }

  Future<void> sendGreenBlinkToStation(String stationId) async {
    try {
      String path = 'stations/$stationId';
      await _rtdb.ref(path).update({
        'command': 'available',
        'timestamp': ServerValue.timestamp,
      }).timeout(const Duration(seconds: 5));
      debugPrint("Green blink (available) command sent to: $stationId");

      // Send via MQTT
      _mqtt.publish('rainnest/$stationId/command', 'available');
    } catch (e) {
      debugPrint("Error sending available command to RTDB: $e");
    }
  }

  // --- Rental Flow (FIFO) ---

  Future<void> sendUnlockCommandToStation(
    String stationId,
    String userId,
  ) async {
    try {
      String path = 'stations/$stationId';
      await _rtdb.ref(path).update({
        'command': 'unlock',
        'current_user': userId,
        'timestamp': ServerValue.timestamp,
      }).timeout(const Duration(seconds: 5));
      debugPrint("Unlock command sent to station: $stationId at path: $path");

      // Send via MQTT
      _mqtt.publish('rainnest/$stationId/rent', 'request');
    } catch (e) {
      debugPrint("Error sending unlock command to RTDB: $e");
    }
  }

  Future<double> getRequiredPayment(String userId) async {
    try {
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
    } catch (e) {
      debugPrint("Error calculating required payment: $e");
      return 110.0; // Default to initial payment on error
    }
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
    try {
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
          // After paying fine and 10 rent, they should be at 100 exactly if they pay exactly enough
          // or more if they had extra. But user's rule is usually reset to 100.
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

        if (station.queueOrder.isEmpty) {
          throw Exception("No umbrellas available");
        }

        // 3. FIFO: Get first umbrella ID
        String umbrellaId = station.queueOrder.first;
        List<String> newQueue = List<String>.from(station.queueOrder)
          ..removeAt(0);

        // --- ALL READS MUST HAPPEN BEFORE ANY WRITES ---
        // Get the Umbrella document NOW before we start updating things
        DocumentReference umbrellaRef = _umbrellasCollection.doc(umbrellaId);
        DocumentSnapshot umbrellaSnap = await transaction.get(umbrellaRef);

        if (umbrellaSnap.exists) {
          final uData = umbrellaSnap.data() as Map<String, dynamic>;
          if (uData['status'] != 'available') {
            throw Exception(
              "Umbrella is not available for rental (Status: ${uData['status']})",
            );
          }
        }

        // --- START WRITES ---

        // 4. Update Station
        double umbrellaResistance = 0.0;
        if (umbrellaSnap.exists) {
          umbrellaResistance =
              (umbrellaSnap.data() as Map<String, dynamic>)['resistance']
                  ?.toDouble() ??
              0.0;
        } else {
          // Re-create resistance from ID if doc doesn't exist (fallback)
          umbrellaResistance = double.tryParse(umbrellaId) ?? 0.0;
        }

        transaction.update(stationRef, {
          'queueOrder': newQueue,
          'availableCount': FieldValue.increment(-1),
          'freeSlotsCount': FieldValue.increment(1),
          'totalResistance': station.totalResistance - umbrellaResistance,
        });

        // 5. Update Umbrella
        if (!umbrellaSnap.exists) {
          // If somehow the umbrella doc was deleted but still in queue,
          // we recreate it to maintain consistency rather than crashing the rental
          transaction.set(umbrellaRef, {
            'umbrellaId': umbrellaId,
            'status': 'rented',
            'stationId': null,
            'createdAt': DateTime.now(),
            'resistance': double.tryParse(umbrellaId) ?? 0.0,
          });
        } else {
          transaction.update(umbrellaRef, {
            'status': 'rented',
            'stationId': null,
          });
        }

        // 6. Update User
        transaction.update(userRef, {
          'activeRentalIds': FieldValue.arrayUnion([umbrellaId]),
          'walletBalance': finalWalletBalance.clamp(
            100.0,
            1000.0,
          ), // Force to 100 minimum if paid
          'securityDeposit': finalWalletBalance.clamp(
            100.0,
            100.0,
          ), // Force to 100
          'hasSecurityDeposit': true,
          'fineAccumulated': 0.0,
        });

        // 7. Record Admin Earnings
        DocumentReference adminRef = _db.collection('admin').doc('stats');
        // We MUST use set with merge: true for the first time it runs,
        // but update will throw 'not found' if the doc was never created.
        // transaction.set with merge: true handles both creation and updating safely.
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
            double topupAmount =
                (addedBalance - 10.0 - fineToClear).clamp(0.0, 1000.0);
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
              description: "Cleared accumulated fines during rental payment",
            );
            transaction.set(finePayRef, finePayTx.toMap());
          }
        }

        // 9. Send Unlock Command to NodeMCU via RTDB
        // This is not awaited as part of the transaction, we do it outside
        // to guarantee it fires even if the transaction resolves slowly
        // But doing it here means it only fires on SUCCESSFUL transaction
        sendUnlockCommandToStation(stationId, userId);

        return {'transactionId': rentTransRef.id, 'umbrellaId': umbrellaId};
      });
    } catch (e) {
      debugPrint("Error in rentUmbrella: $e");
      rethrow;
    }
  }

  Future<void> requestRedemption(String userId) async {
    try {
      final userSnap = await _usersCollection.doc(userId).get();
      if (!userSnap.exists) throw Exception("User not found");
      final user = UserModel.fromMap(userSnap.data() as Map<String, dynamic>);

      if (user.activeRentalIds.isNotEmpty) {
        throw Exception(
          "Please return all umbrellas before requesting a deposit refund.",
        );
      }

      if (user.redemptionBlocked) {
        throw Exception(
          "Your account redemption is currently blocked. Please contact support.",
        );
      }

      await _usersCollection.doc(userId).update({
        'redemptionStatus': 'pending',
        'redemptionRequestedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("Error requesting redemption: $e");
      rethrow;
    }
  }

  Future<void> redeemSecurityDeposit(String userId) async {
    try {
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
    } catch (e) {
      debugPrint("Error redeeming security deposit: $e");
      rethrow;
    }
  }

  Future<void> cancelRedemption(String userId) async {
    try {
      await _usersCollection.doc(userId).update({
        'redemptionStatus': null,
        'redemptionRequestedAt': null,
      });
    } catch (e) {
      debugPrint("Error cancelling redemption: $e");
    }
  }

  Future<void> toggleUserRedemptionBlock(String userId, bool isBlocked) async {
    try {
      await _usersCollection.doc(userId).update({
        'redemptionBlocked': isBlocked,
      });
    } catch (e) {
      debugPrint("Error toggling redemption block: $e");
      rethrow;
    }
  }

  Future<List<UserModel>> getUsersAssociatedWithUmbrella(
    String umbrellaId,
  ) async {
    try {
      List<UserModel> users = [];

      // 1. Check current user renting it
      final userSnap = await _usersCollection
          .where('activeRentalIds', arrayContains: umbrellaId)
          .get();

      for (var doc in userSnap.docs) {
        users.add(UserModel.fromMap(doc.data() as Map<String, dynamic>));
      }

      // 2. Check lastUserId on the umbrella
      final umbrellaSnap = await _umbrellasCollection.doc(umbrellaId).get();
      if (umbrellaSnap.exists) {
        final lastUserId = umbrellaSnap.get('lastUserId') as String?;
        if (lastUserId != null && !users.any((u) => u.uid == lastUserId)) {
          final lastUser = await getUser(lastUserId);
          if (lastUser != null) users.add(lastUser);
        }
      }

      return users;
    } catch (e) {
      debugPrint("Error getting users associated with umbrella: $e");
      return [];
    }
  }

  Future<List<UserModel>> getBlockedUsers() async {
    try {
      final snapshot = await _usersCollection
          .where('redemptionBlocked', isEqualTo: true)
          .get();
      return snapshot.docs
          .map((doc) => UserModel.fromMap(doc.data() as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint("Error getting blocked users: $e");
      return [];
    }
  }

  Future<void> collectBlockedWalletAsFine(String userId) async {
    await _db.runTransaction((transaction) async {
      DocumentReference userRef = _usersCollection.doc(userId);
      DocumentSnapshot userSnap = await transaction.get(userRef);

      if (!userSnap.exists) throw Exception("User not found");
      final user = UserModel.fromMap(userSnap.data() as Map<String, dynamic>);

      double amount = user.walletBalance;

      // Reset wallet and block status
      transaction.update(userRef, {
        'walletBalance': 0.0,
        'securityDeposit': 0.0,
        'hasSecurityDeposit': false,
        'redemptionBlocked': false,
        'fineAccumulated': 0.0, // Clear accumulated fine as we took the deposit
        'redemptionStatus': 'none',
        'redemptionRequestedAt': null,
      });

      // Record transaction
      DocumentReference txRef = _transactionsCollection.doc();
      transaction.set(txRef, {
        'transactionId': txRef.id,
        'userId': userId,
        'amount': -amount,
        'type': 'fine_collection',
        'status': 'success',
        'timestamp': FieldValue.serverTimestamp(),
        'description': "Security deposit collected as fine (Admin Action)",
      });
    });
  }

  // --- Return Flow ---

  Future<void> sendReturnCommandToStation(
    String stationId,
    String userId,
  ) async {
    try {
      String path = 'stations/$stationId';
      await _rtdb.ref(path).update({
        'command': 'return',
        'current_user': userId,
        'timestamp': ServerValue.timestamp,
      }).timeout(const Duration(seconds: 5));
      debugPrint("Return command sent to station: $stationId at path: $path");

      // Send via MQTT
      _mqtt.publish('rainnest/stations/$stationId/commands', 'return:$userId');
    } catch (e) {
      debugPrint("Error sending return command to RTDB: $e");
    }
  }

  Future<Map<String, dynamic>> processFullReturn({
    required String transactionId,
    required String userId,
    required String stationId,
    required String umbrellaId,
    bool isDamaged = false,
    bool isPreRental = false,
    String? damageType,
  }) async {
    try {
      return await _db.runTransaction((transaction) async {
        // 1. Get Rental Transaction
        DocumentReference originalTransRef = _transactionsCollection.doc(transactionId);
        DocumentSnapshot originalTransSnap = await transaction.get(originalTransRef);
        if (!originalTransSnap.exists) {
          throw Exception("Rental record not found");
        }

        TransactionModel originalTx = TransactionModel.fromMap(
          originalTransSnap.data() as Map<String, dynamic>,
          originalTransSnap.id,
        );

        if (originalTx.status == 'success') {
          throw Exception("Rental already returned");
        }

        // Send 'return' command to NodeMCU
        sendReturnCommandToStation(stationId, userId);

        // 2. Calculate Penalty
        final now = DateTime.now();
        final diff = now.difference(originalTx.timestamp);
        final totalMinutes = diff.inMinutes;
        double totalPenalty = 0.0;

        if (!isPreRental && totalMinutes > 600) {
          int overdueHours = (totalMinutes / 60.0).ceil() - 10;
          totalPenalty = overdueHours * 5.0;
        }

        // 3. Get User
        DocumentReference userRef = _usersCollection.doc(userId);
        DocumentSnapshot userSnap = await transaction.get(userRef);
        if (!userSnap.exists) throw Exception("User not found");
        UserModel user = UserModel.fromMap(userSnap.data() as Map<String, dynamic>);

        if (!user.activeRentalIds.contains(umbrellaId)) {
          throw Exception("Umbrella not found in active rentals");
        }

        double extraPenalty = (totalPenalty - originalTx.penaltyAmount).clamp(0.0, 1000.0);

        // 4. Update Station
        DocumentReference stationRef = _stationsCollection.doc(stationId);
        DocumentSnapshot stationSnap = await transaction.get(stationRef);
        if (!stationSnap.exists) throw Exception("Station not found");
        Station station = Station.fromMap(stationSnap.data() as Map<String, dynamic>, stationSnap.id);

        // 5. Calculate New Balances
        double refundAmount = isPreRental ? 10.0 : 0.0;
        double newWalletBalance = user.walletBalance + refundAmount;
        double finalFineAccumulated = user.fineAccumulated;

        if (extraPenalty > 0) {
          if (newWalletBalance >= extraPenalty) {
            newWalletBalance -= extraPenalty;
          } else {
            double remainingExtra = extraPenalty - newWalletBalance;
            newWalletBalance = 0.0;
            finalFineAccumulated += remainingExtra;
          }
        }

        // 6. Update Umbrella
        DocumentReference umbrellaRef = _umbrellasCollection.doc(umbrellaId);
        DocumentSnapshot umbrellaSnap = await transaction.get(umbrellaRef);
        String finalStatus = isDamaged ? 'damaged' : 'available';

        if (umbrellaSnap.exists && !isDamaged) {
          final uData = umbrellaSnap.data() as Map<String, dynamic>;
          if (uData['status'] == 'maintenance') finalStatus = 'maintenance';
        }

        bool addToQueue = finalStatus == 'available';
        List<String> newQueue = List<String>.from(station.queueOrder);
        if (addToQueue && !newQueue.contains(umbrellaId)) {
          newQueue.add(umbrellaId);
        }

        double umbrellaResistance = 0.0;
        if (umbrellaSnap.exists) {
          umbrellaResistance = (umbrellaSnap.data() as Map<String, dynamic>)['resistance']?.toDouble() ?? 0.0;
        } else {
          umbrellaResistance = double.tryParse(umbrellaId) ?? 0.0;
        }

        // --- Writes ---
        transaction.update(stationRef, {
          'queueOrder': newQueue,
          'availableCount': FieldValue.increment(addToQueue ? 1 : 0),
          'freeSlotsCount': FieldValue.increment(-1),
          'totalResistance': station.totalResistance + umbrellaResistance,
        });

        int coinsAwarded = (totalPenalty == 0 && !isPreRental) ? _randomCoinReward() : 0;

        transaction.update(userRef, {
          'activeRentalIds': FieldValue.arrayRemove([umbrellaId]),
          'walletBalance': newWalletBalance.clamp(0.0, 1000.0),
          'coins': FieldValue.increment(coinsAwarded),
          'securityDeposit': newWalletBalance.clamp(0.0, 100.0),
          'hasSecurityDeposit': newWalletBalance >= 100.0,
          'fineAccumulated': finalFineAccumulated,
        });

        transaction.update(umbrellaRef, {
          'status': finalStatus,
          'stationId': stationId,
          'lastDamageReport': isDamaged ? damageType : null,
          'lastUserId': userId,
        });

        transaction.update(originalTransRef, {
          'status': 'success',
          'penaltyAmount': totalPenalty,
          'returnTimestamp': FieldValue.serverTimestamp(),
          'condition': isDamaged ? 'damaged' : 'ok',
        });

        // Transactions Logging
        if (totalPenalty > 0) {
          DocumentReference penaltyTxRef = _transactionsCollection.doc();
          transaction.set(penaltyTxRef, TransactionModel(
            transactionId: penaltyTxRef.id,
            userId: userId,
            umbrellaId: umbrellaId,
            penaltyAmount: totalPenalty,
            status: 'success',
            type: 'penalty',
            timestamp: DateTime.now(),
          ).toMap());
        }

        if (coinsAwarded > 0) {
          DocumentReference coinTxRef = _transactionsCollection.doc();
          transaction.set(coinTxRef, TransactionModel(
            transactionId: coinTxRef.id,
            userId: userId,
            umbrellaId: umbrellaId,
            coins: coinsAwarded,
            status: 'success',
            type: 'coin_reward',
            timestamp: DateTime.now(),
          ).toMap());
        }

        if (isDamaged) {
          DocumentReference damageRef = _db.collection('damage_reports').doc();
          transaction.set(damageRef, {
            'reportId': damageRef.id,
            'umbrellaId': umbrellaId,
            'userId': userId,
            'reporterName': user.name,
            'reporterPhone': user.phoneNumber,
            'type': damageType,
            'timestamp': FieldValue.serverTimestamp(),
            'status': 'pending_review',
            'timing': isPreRental ? 'before_rental' : 'after_rental',
          });
        }

        if (isPreRental) {
          DocumentReference refundTxRef = _transactionsCollection.doc();
          transaction.set(refundTxRef, {
            'transactionId': refundTxRef.id,
            'userId': userId,
            'umbrellaId': umbrellaId,
            'amount': 10.0,
            'type': 'rental_refund',
            'status': 'success',
            'timestamp': FieldValue.serverTimestamp(),
            'description': "Refund for damaged umbrella (Pre-rental report)",
          });
          transaction.set(_db.collection('admin').doc('stats'), {
            'totalEarnings': FieldValue.increment(-10.0),
          }, SetOptions(merge: true));
        } else if (extraPenalty > 0) {
          DocumentReference penaltyTransRef = _transactionsCollection.doc();
          transaction.set(penaltyTransRef, TransactionModel(
            transactionId: penaltyTransRef.id,
            userId: userId,
            umbrellaId: umbrellaId,
            penaltyAmount: extraPenalty,
            status: 'success',
            type: 'penalty',
            timestamp: DateTime.now(),
            description: "Final fine deduction at return",
          ).toMap());

          transaction.set(_db.collection('admin').doc('stats'), {
            'totalFineCollected': FieldValue.increment(extraPenalty),
          }, SetOptions(merge: true));
        }

        DocumentReference returnTransRef = _transactionsCollection.doc();
        transaction.set(returnTransRef, TransactionModel(
          transactionId: returnTransRef.id,
          userId: userId,
          umbrellaId: umbrellaId,
          rentalAmount: 0.0,
          status: 'success',
          type: 'return',
          timestamp: DateTime.now(),
        ).toMap());

        return {
          'penalty': totalPenalty,
          'refund': refundAmount,
          'duration': diff.inMinutes,
          'timestamp': now,
          'coinsAwarded': coinsAwarded,
        };
      });
    } catch (e) {
      debugPrint("Error in processFullReturn: $e");
      rethrow;
    }
  }

  // --- Coin Helpers ---

  /// Returns a random weighted coin reward.
  /// Weights: 70% → 1–10, 20% → 11–25, 10% → 26–50
  int _randomCoinReward() {
    final rng = math.Random();
    final roll = rng.nextDouble(); // 0.0–1.0
    if (roll < 0.70) {
      return rng.nextInt(10) + 1; // 1–10
    } else if (roll < 0.90) {
      return rng.nextInt(15) + 11; // 11–25
    } else {
      return rng.nextInt(25) + 26; // 26–50
    }
  }

  /// Redeems 10,000 coins (= ₹10).
  /// [mode] can be 'wallet' (add ₹10 to wallet) or 'free_rental' (grant a free rental credit).
  Future<void> redeemCoins(String userId, {String mode = 'wallet'}) async {
    try {
      await _db.runTransaction((transaction) async {
        DocumentReference userRef = _usersCollection.doc(userId);
        DocumentSnapshot userSnap = await transaction.get(userRef);
        if (!userSnap.exists) throw Exception("User not found");

        UserModel user = UserModel.fromMap(
          userSnap.data() as Map<String, dynamic>,
        );

        const int requiredCoins = 10000;
        if (user.coins < requiredCoins) {
          throw Exception(
            "Not enough coins. You need $requiredCoins coins to redeem.",
          );
        }

        final Map<String, dynamic> userUpdates = {
          'coins': FieldValue.increment(-requiredCoins),
        };

        if (mode == 'wallet') {
          // Add ₹10 to wallet
          userUpdates['walletBalance'] = FieldValue.increment(10.0);
        } else if (mode == 'free_rental') {
          // Grant a free rental credit flag
          userUpdates['freeRentalCredits'] = FieldValue.increment(1);
        }

        transaction.update(userRef, userUpdates);

        // Record the redemption transaction
        DocumentReference redeemRef = _transactionsCollection.doc();
        transaction.set(redeemRef, {
          'transactionId': redeemRef.id,
          'userId': userId,
          'type': 'coin_redeem',
          'coins': -requiredCoins,
          'rentalAmount': mode == 'wallet' ? 10.0 : 0.0,
          'status': 'success',
          'redeemMode': mode,
          'timestamp': DateTime.now(),
        });
      });
    } catch (e) {
      debugPrint("Error redeeming coins: $e");
      rethrow;
    }
  }

  // Backward compatibility wrapper for old return flow
  Future<void> returnUmbrella({
    required String transactionId,
    required String userId,
    required String stationId,
    required String umbrellaId,
    bool isDamaged = false,
    bool isPreRental = false,
    String? damageType,
  }) async {
    await processFullReturn(
      transactionId: transactionId,
      userId: userId,
      stationId: stationId,
      umbrellaId: umbrellaId,
      isDamaged: isDamaged,
      isPreRental: isPreRental,
      damageType: damageType,
    );
  }

  /// Syncs fines for all active rentals of a user
  /// Calculated as ₹5/hr after 10hr free period
  Future<void> syncActiveFines(String userId) async {
    try {
      final userSnap = await _usersCollection.doc(userId).get();
      if (!userSnap.exists) return;
      UserModel user = UserModel.fromMap(
        userSnap.data() as Map<String, dynamic>,
      );

      if (user.activeRentalIds.isEmpty) return;

      // Get the most recent rental transactions for these umbrellas
      final rentalsSnap = await _transactionsCollection
          .where('userId', isEqualTo: userId)
          .where('type', isEqualTo: 'rental_fee')
          .get();

      double totalNewWalletBalance = user.walletBalance;
      double totalNewFineAccumulated = user.fineAccumulated;
      final now = DateTime.now();
      double totalDeductedFromWallet = 0.0;

      for (var doc in rentalsSnap.docs) {
        final tx = TransactionModel.fromMap(
          doc.data() as Map<String, dynamic>,
          doc.id,
        );

        if (user.activeRentalIds.contains(tx.umbrellaId) &&
            (tx.status == 'active' || tx.status == 'late')) {
          final totalMinutes = now.difference(tx.timestamp).inMinutes;

          if (totalMinutes > 600) {
            int overdueHours = (totalMinutes / 60.0).ceil() - 10;
            double currentFineDue = overdueHours * 5.0;

            // Delta fine since last recorded in transaction
            double fineDelta = currentFineDue - tx.penaltyAmount;

            if (fineDelta > 0) {
              double deductedFromWallet = 0.0;
              // Deduct from wallet if possible
              if (totalNewWalletBalance >= fineDelta) {
                deductedFromWallet = fineDelta;
                totalNewWalletBalance -= fineDelta;
              } else {
                // Wallet emptied, rest goes to fineAccumulated
                deductedFromWallet = totalNewWalletBalance;
                double remainingFine = fineDelta - totalNewWalletBalance;
                totalNewWalletBalance = 0.0;
                totalNewFineAccumulated += remainingFine;
              }

              totalDeductedFromWallet += deductedFromWallet;

              // Update transaction's penaltyAmount (tracking what's applied to it)
              await _transactionsCollection.doc(tx.transactionId).update({
                'penaltyAmount': currentFineDue,
                'status': 'late',
              });

              // Record the deduction as a separate penalty transaction record
              if (deductedFromWallet > 0) {
                DocumentReference penaltyRef = _transactionsCollection.doc();
                await penaltyRef.set({
                  'transactionId': penaltyRef.id,
                  'userId': userId,
                  'umbrellaId': tx.umbrellaId,
                  'penaltyAmount': deductedFromWallet,
                  'type': 'penalty',
                  'status': 'success',
                  'timestamp': FieldValue.serverTimestamp(),
                  'description': "Automatic fine deduction from wallet",
                });
              }
            }
          }
        }
      }

      if (totalDeductedFromWallet > 0 || totalNewFineAccumulated != user.fineAccumulated) {
        await _usersCollection.doc(userId).update({
          'walletBalance': totalNewWalletBalance.clamp(0.0, 1000.0),
          'fineAccumulated': totalNewFineAccumulated,
        });

        if (totalDeductedFromWallet > 0) {
          DocumentReference adminRef = _db.collection('admin').doc('stats');
          await adminRef.set({
            'totalFineCollected': FieldValue.increment(totalDeductedFromWallet),
          }, SetOptions(merge: true));
        }
      }
    } catch (e) {
      debugPrint("Error syncing active fines: $e");
    }
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

  Future<List<TransactionModel>> getActiveRentalsForUmbrella(String umbrellaId) async {
    final snapshot = await _transactionsCollection
        .where('umbrellaId', isEqualTo: umbrellaId)
        .where('status', isEqualTo: 'active')
        .get();
    return snapshot.docs
        .map((doc) => TransactionModel.fromMap(doc.data() as Map<String, dynamic>, doc.id))
        .toList();
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
    try {
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
        // Update existing - preserve maintenance/damaged status
        final existingData = umbrellaSnap.data() as Map<String, dynamic>;
        String finalStatus = status;
        String currentStatus = existingData['status'] ?? 'available';

        if (currentStatus == 'maintenance' || currentStatus == 'damaged') {
          // Hardware sync should NOT clear admin-set restrictions
          finalStatus = currentStatus;
        }

        await umbrellaRef.update({
          'stationId': stationId,
          'status': finalStatus,
        });
      }
    } catch (e) {
      debugPrint("Error updating umbrella from hardware: $e");
    }
  }

  Future<bool> isQrCodeUnique(String qrCode, {String? excludeStationId}) async {
    try {
      Query query = _stationsCollection.where(
        'machineQrCode',
        isEqualTo: qrCode,
      );
      final snapshot = await query.get();

      if (excludeStationId != null) {
        return snapshot.docs.where((doc) => doc.id != excludeStationId).isEmpty;
      }
      return snapshot.docs.isEmpty;
    } catch (e) {
      debugPrint("Error checking QR code uniqueness: $e");
      return false; // Safest fallback
    }
  }

  Future<DocumentReference?> addStation(Station station) async {
    try {
      return await _stationsCollection.add(station.toMap());
    } catch (e) {
      debugPrint("Error adding station: $e");
      return null;
    }
  }

  Future<void> updateStation(Station station) async {
    try {
      await _stationsCollection.doc(station.stationId).update(station.toMap());
    } catch (e) {
      debugPrint("Error updating station: $e");
      rethrow;
    }
  }

  Future<void> deleteStation(String stationId) async {
    try {
      await _stationsCollection.doc(stationId).delete();
    } catch (e) {
      debugPrint("Error deleting station: $e");
      rethrow;
    }
  }

  Future<void> saveUmbrella(Umbrella umbrella) async {
    try {
      // 1. Write to Firestore
      await _umbrellasCollection.doc(umbrella.umbrellaId).set(umbrella.toMap());

      // 2. Write Resistance to RTDB for NodeMCU (Registry)
      await _rtdb.ref('umbrella_registry/${umbrella.umbrellaId}').set({
        'id': umbrella.umbrellaId,
        'res': umbrella.resistance,
      });
    } catch (e) {
      debugPrint("Error saving umbrella: $e");
      rethrow;
    }
  }

  Future<List<Station>> getAllStations() async {
    try {
      final snap = await _stationsCollection.get();
      return snap.docs.map((doc) {
        return Station.fromMap(doc.data() as Map<String, dynamic>, doc.id);
      }).toList();
    } catch (e) {
      debugPrint("Error getting all stations: $e");
      return [];
    }
  }

  Future<Map<int, Map<String, double>>> getMonthlyRentalStats(
    int month,
    int year,
  ) async {
    try {
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
    } catch (e) {
      debugPrint("Error in getMonthlyRentalStats: $e");
      return {};
    }
  }

  Stream<List<Map<String, dynamic>>> getDamageReportsStream() {
    return _db
        .collection('damage_reports')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            final data = doc.data();
            return {'id': doc.id, ...data};
          }).toList();
        });
  }

  Future<void> updateDamageReportStatus(String reportId, String status) async {
    await _db.collection('damage_reports').doc(reportId).update({
      'status': status,
    });
  }

  Future<void> deleteDamageReport(String reportId) async {
    await _db.collection('damage_reports').doc(reportId).delete();
  }

  /// Blocks security deposit by adding a fine to the user
  Future<void> blockSecurityDeposit({
    required String userId,
    required String reportId,
    required double amount,
    required String reason,
  }) async {
    await _db.runTransaction((transaction) async {
      DocumentReference userRef = _usersCollection.doc(userId);
      DocumentSnapshot userSnap = await transaction.get(userRef);
      if (!userSnap.exists) throw Exception("User not found");

      UserModel user = UserModel.fromMap(
        userSnap.data() as Map<String, dynamic>,
      );

      // Add to fineAccumulated and deduct from walletBalance
      double newWalletBalance = (user.walletBalance - amount).clamp(
        0.0,
        1000.0,
      );
      double additionalFine = (amount - user.walletBalance).clamp(0.0, 1000.0);

      transaction.update(userRef, {
        'walletBalance': newWalletBalance,
        'fineAccumulated': user.fineAccumulated + additionalFine,
        'securityDeposit': newWalletBalance.clamp(0.0, 100.0),
        'hasSecurityDeposit': newWalletBalance >= 100.0,
      });

      // Record transaction
      DocumentReference txRef = _transactionsCollection.doc();
      transaction.set(txRef, {
        'transactionId': txRef.id,
        'userId': userId,
        'amount': -amount,
        'type': 'security_block',
        'status': 'success',
        'timestamp': FieldValue.serverTimestamp(),
        'description': "Blocked deposit: $reason",
      });

      // Link to damage report
      transaction.update(_db.collection('damage_reports').doc(reportId), {
        'status': 'deposit_blocked',
        'blockedUserId': userId,
        'blockedAmount': amount,
      });
    });
  }

  Future<void> submitPreRentalDamageReport({
    required String umbrellaId,
    required String reporterId,
    required String damageType,
  }) async {
    // 1. Get Reporter info
    final reporter = await getUser(reporterId);
    if (reporter == null) throw Exception("Reporter not found");

    // 2. Get Umbrella info to find last user
    final umbrellaDoc = await _umbrellasCollection.doc(umbrellaId).get();
    if (!umbrellaDoc.exists) throw Exception("Umbrella not found");
    final umbrellaData = umbrellaDoc.data() as Map<String, dynamic>;
    final lastUserId = umbrellaData['lastUserId'];

    // 3. Create report
    DocumentReference damageRef = _db.collection('damage_reports').doc();
    await damageRef.set({
      'reportId': damageRef.id,
      'umbrellaId': umbrellaId,
      'userId': reporterId,
      'reporterName': reporter.name,
      'reporterPhone': reporter.phoneNumber,
      'lastUserId': lastUserId,
      'type': damageType,
      'timestamp': FieldValue.serverTimestamp(),
      'status': 'pending_review',
      'timing': 'before_rental',
    });

    // 4. Put umbrella in maintenance
    await _umbrellasCollection.doc(umbrellaId).update({
      'status': 'maintenance',
      'lastDamageReport': damageType,
    });
  }

  Future<void> updateUmbrellaStatus(String umbrellaId, String status) async {
    await _umbrellasCollection.doc(umbrellaId).update({'status': status});
  }

  Future<void> toggleUmbrellaMaintenance(
    String umbrellaId,
    bool isMaintenance,
  ) async {
    try {
      await _db.runTransaction((transaction) async {
        // 1. Get Umbrella
        DocumentReference umbrellaRef = _umbrellasCollection.doc(umbrellaId);
        DocumentSnapshot umbrellaSnap = await transaction.get(umbrellaRef);
        if (!umbrellaSnap.exists) throw Exception("Umbrella not found");

        Umbrella umbrella = Umbrella.fromMap(
          umbrellaSnap.data() as Map<String, dynamic>,
        );

        String? stationId = umbrella.stationId;
        String newStatus = isMaintenance ? 'maintenance' : 'available';

        // 3. Prepare Station Update (Get snapshot before any write)
        DocumentSnapshot? stationSnap;
        if (stationId != null) {
          stationSnap = await transaction.get(
            _stationsCollection.doc(stationId),
          );
        }

        // --- START WRITES ---

        // 2. Update Umbrella Status
        transaction.update(umbrellaRef, {'status': newStatus});

        // 4. Update Station if umbrella is currently at a station
        if (stationId != null && stationSnap != null && stationSnap.exists) {
          final data = stationSnap.data() as Map<String, dynamic>?;
          if (data != null) {
            List<String> queueOrder = List<String>.from(
              data['queueOrder'] ?? [],
            );

            if (isMaintenance) {
              if (queueOrder.contains(umbrellaId)) {
                queueOrder.remove(umbrellaId);
                transaction.update(_stationsCollection.doc(stationId), {
                  'queueOrder': queueOrder,
                  'availableCount': FieldValue.increment(-1),
                });
              }
            } else {
              if (!queueOrder.contains(umbrellaId)) {
                queueOrder.add(umbrellaId);
                transaction.update(_stationsCollection.doc(stationId), {
                  'queueOrder': queueOrder,
                  'availableCount': FieldValue.increment(1),
                });
              }
            }
          }
        }
      });
    } catch (e) {
      debugPrint("Error toggling maintenance: $e");
      rethrow;
    }
  }

  Stream<List<Umbrella>> getUmbrellasStream() {
    return _umbrellasCollection.snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => Umbrella.fromMap(doc.data() as Map<String, dynamic>))
          .toList();
    });
  }
}
