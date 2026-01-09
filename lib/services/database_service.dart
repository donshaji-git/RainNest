import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/models/user_model.dart';
import '../data/models/umbrella_location.dart';

class DatabaseService {
  final CollectionReference _usersCollection = FirebaseFirestore.instance
      .collection('users');

  final CollectionReference _umbrellaLocationsCollection = FirebaseFirestore
      .instance
      .collection('station_machines');

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

  Future<bool> userExists(String uid) async {
    DocumentSnapshot doc = await _usersCollection.doc(uid).get();
    return doc.exists;
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

  Future<void> deleteUmbrellaLocation(String locationId) async {
    await _umbrellaLocationsCollection.doc(locationId).delete();
  }
}
