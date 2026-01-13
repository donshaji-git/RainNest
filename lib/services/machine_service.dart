import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import '../data/models/umbrella_location.dart';

class MachineService {
  final CollectionReference _machinesCollection = FirebaseFirestore.instance
      .collection('station_machines');

  Stream<List<UmbrellaLocation>> getMachines() {
    return _machinesCollection.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return UmbrellaLocation.fromMap(
          doc.data() as Map<String, dynamic>,
          doc.id,
        );
      }).toList();
    });
  }

  static double calculateDistance(LatLng point1, LatLng point2) {
    const Distance distance = Distance();
    return distance.as(LengthUnit.Meter, point1, point2);
  }

  static String formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.toStringAsFixed(0)}m away';
    } else {
      return '${(meters / 1000).toStringAsFixed(1)}km away';
    }
  }
}
