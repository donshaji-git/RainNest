import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../data/models/umbrella_location.dart';
import '../services/database_service.dart';
import '../services/location_service.dart';

class StationProvider with ChangeNotifier {
  final DatabaseService _db = DatabaseService();
  StreamSubscription<List<UmbrellaLocation>>? _stationsSubscription;

  List<UmbrellaLocation> _allStations = [];
  List<UmbrellaLocation> _nearbyStations = [];
  bool _isLoading = true;
  String? _errorMessage;

  List<UmbrellaLocation> get stations => _nearbyStations;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  UmbrellaLocation? get nearestStation =>
      _nearbyStations.isNotEmpty ? _nearbyStations.first : null;

  void initialize(LatLng? userLocation) {
    if (_stationsSubscription != null) return;

    _isLoading = true;
    notifyListeners();

    try {
      _stationsSubscription = _db.getUmbrellaLocations().listen(
        (data) {
          _allStations = data;
          _sortStations(userLocation);
          _isLoading = false;
          _errorMessage = null;
          notifyListeners();
        },
        onError: (error) {
          _errorMessage = 'Error loading stations: $error';
          _isLoading = false;
          debugPrint(_errorMessage);
          notifyListeners();
        },
      );
    } catch (e) {
      _errorMessage = 'Unexpected error: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  void updateLocation(LatLng? userLocation) {
    if (userLocation == null) return;
    _sortStations(userLocation);
    notifyListeners();
  }

  void _sortStations(LatLng? userLocation) {
    if (userLocation == null) {
      _nearbyStations = List.from(_allStations);
      return;
    }

    _nearbyStations = List.from(_allStations);
    _nearbyStations.sort((a, b) {
      final distA = LocationService.calculateHaversineDistance(
        userLocation.latitude,
        userLocation.longitude,
        a.latitude,
        a.longitude,
      );
      final distB = LocationService.calculateHaversineDistance(
        userLocation.latitude,
        userLocation.longitude,
        b.latitude,
        b.longitude,
      );
      return distA.compareTo(distB);
    });
  }

  Future<LatLng?> searchLocation(String query) async {
    try {
      final results = await LocationService.searchPlaces(query);
      if (results.isNotEmpty) {
        return results.first.location;
      }
    } catch (e) {
      debugPrint('Search failed: $e');
    }
    return null;
  }

  @override
  void dispose() {
    _stationsSubscription?.cancel();
    super.dispose();
  }
}
