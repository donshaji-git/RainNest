import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class MapProvider with ChangeNotifier {
  final MapController _mapController = MapController();

  MapController get mapController => _mapController;

  /// Move camera to a specific location with zoom
  void moveTo(LatLng point, double zoom) {
    _mapController.move(point, zoom);
  }

  /// Center map on user location
  void centerOnUser(LatLng userLocation) {
    _mapController.move(userLocation, 15.0);
  }

  /// Animate camera to nearest machine
  void animateToNearest(LatLng machineLocation) {
    // Basic implementation using move.
    // For smoother "animation", we can implement a custom Ticker-based animation if needed,
    // but flutter_map's move is standard.
    _mapController.move(machineLocation, 16.0);
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }
}
