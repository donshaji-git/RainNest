import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/models/user_model.dart';
import '../data/models/umbrella_location.dart';
import '../data/models/umbrella.dart';
import '../data/models/umbrella_rental.dart';
import '../data/models/payment.dart';

class DatabaseService {
  final CollectionReference _usersCollection = FirebaseFirestore.instance
      .collection('users');

  final CollectionReference _umbrellaLocationsCollection = FirebaseFirestore
      .instance
      .collection('station_machines');

  final CollectionReference _umbrellasCollection = FirebaseFirestore.instance
      .collection('umbrellas');

  final CollectionReference _rentalsCollection = FirebaseFirestore.instance
      .collection('umbrella_rentals');

  final CollectionReference _paymentsCollection = FirebaseFirestore.instance
      .collection('payments');

  Future<void> saveUser(UserModel user) async {
    await _usersCollection.doc(user.uid).set(user.toMap());
  }

  Future<void> updateUserWallet(String uid, double newBalance) async {
    await _usersCollection.doc(uid).update({'walletBalance': newBalance});
  }

  Future<void> updateUserRentalStatus(
    String uid, {
    required bool isRented,
    String? activeRentalId,
  }) async {
    await _usersCollection.doc(uid).update({
      'isRented': isRented,
      'activeRentalId': activeRentalId,
    });
  }

  Future<UserModel?> getUser(String uid) async {
    DocumentSnapshot doc = await _usersCollection.doc(uid).get();
    if (doc.exists) {
      return UserModel.fromMap(doc.data() as Map<String, dynamic>);
    }
    return null;
  }

  Future<bool> userExists(String uid) async {
    DocumentSnapshot doc = await _usersCollection.doc(uid).get();
    return doc.exists;
  }

  // Umbrella Methods

  Future<void> saveUmbrella(Umbrella umbrella) async {
    await _umbrellasCollection.doc(umbrella.id).set(umbrella.toMap());
  }

  Future<Umbrella?> getUmbrella(String id) async {
    DocumentSnapshot doc = await _umbrellasCollection.doc(id).get();
    if (doc.exists) {
      return Umbrella.fromMap(doc.data() as Map<String, dynamic>);
    }
    return null;
  }

  // Rental Methods

  Future<String> createRental(UmbrellaRental rental) async {
    DocumentReference doc = await _rentalsCollection.add(rental.toMap());
    return doc.id;
  }

  Future<void> updateRental(UmbrellaRental rental) async {
    await _rentalsCollection.doc(rental.id).update(rental.toMap());
  }

  Future<UmbrellaRental?> getRental(String id) async {
    DocumentSnapshot doc = await _rentalsCollection.doc(id).get();
    if (doc.exists) {
      return UmbrellaRental.fromMap(doc.data() as Map<String, dynamic>, doc.id);
    }
    return null;
  }

  Future<UmbrellaRental?> getLastCompletedRental(String umbrellaId) async {
    final query = await _rentalsCollection
        .where('umbrellaId', isEqualTo: umbrellaId)
        .where('status', isEqualTo: 'completed')
        .orderBy('returnTime', descending: true)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      return UmbrellaRental.fromMap(
        query.docs.first.data() as Map<String, dynamic>,
        query.docs.first.id,
      );
    }
    return null;
  }

  // Payment Methods

  Future<void> recordPayment(Payment payment) async {
    await _paymentsCollection.add(payment.toMap());
  }

  // Umbrella Locations Methods

  Stream<List<UmbrellaLocation>> getUmbrellaLocations() {
    return _umbrellaLocationsCollection.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return UmbrellaLocation.fromMap(
          doc.data() as Map<String, dynamic>,
          doc.id,
        );
      }).toList();
    });
  }

  Future<void> addUmbrellaLocation(UmbrellaLocation location) async {
    await _umbrellaLocationsCollection.add(location.toMap());
  }

  Future<void> updateUmbrellaLocation(UmbrellaLocation location) async {
    await _umbrellaLocationsCollection
        .doc(location.id)
        .update(location.toMap());
  }

  Future<UmbrellaLocation?> getUmbrellaLocation(String id) async {
    DocumentSnapshot doc = await _umbrellaLocationsCollection.doc(id).get();
    if (doc.exists) {
      return UmbrellaLocation.fromMap(
        doc.data() as Map<String, dynamic>,
        doc.id,
      );
    }
    return null;
  }

  Future<void> updateUmbrellaCounts(
    String machineId, {
    required int deltaUmbrellas,
  }) async {
    // deltaUmbrellas: -1 for rent, +1 for return
    await _umbrellaLocationsCollection.doc(machineId).update({
      'availableUmbrellas': FieldValue.increment(deltaUmbrellas),
      'availableReturnSlots': FieldValue.increment(-deltaUmbrellas),
    });
  }

  Future<void> deleteUmbrellaLocation(String locationId) async {
    await _umbrellaLocationsCollection.doc(locationId).delete();
  }
}
