import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../services/location_service.dart';

class LocationProvider with ChangeNotifier {
  LatLng? _currentLocation;
  LocationPermissionState _permissionState = LocationPermissionState.denied;
  bool _isServiceEnabled = true;
  bool _isLoading = false;
  String? _errorMessage;

  LatLng? get currentLocation => _currentLocation;
  LocationPermissionState get permissionState => _permissionState;
  bool get isServiceEnabled => _isServiceEnabled;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasLocation => _currentLocation != null;

  /// Initialize and request location
  Future<void> initialize() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Check and request permission
      final state = await LocationService.checkAndRequestPermission();
      _permissionState = state;

      if (state == LocationPermissionState.granted) {
        // Get current position
        final position = await LocationService.getCurrentPosition();
        if (position != null) {
          _currentLocation = LatLng(position.latitude, position.longitude);
          _errorMessage = null;
        } else {
          _errorMessage = 'Unable to get current location';
        }
      } else if (state == LocationPermissionState.disabled) {
        _isServiceEnabled = false;
        _errorMessage = 'Location service is disabled';
      } else {
        _errorMessage = 'Location permission denied';
      }
    } catch (e) {
      _errorMessage = 'Error getting location: $e';
      debugPrint(_errorMessage);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Refresh current location
  Future<void> refreshLocation() async {
    if (_permissionState != LocationPermissionState.granted) {
      await initialize();
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      final position = await LocationService.getCurrentPosition();
      if (position != null) {
        _currentLocation = LatLng(position.latitude, position.longitude);
        _errorMessage = null;
      }
    } catch (e) {
      _errorMessage = 'Error refreshing location: $e';
      debugPrint(_errorMessage);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Open app settings for location permission
  Future<void> openSettings() async {
    await Geolocator.openAppSettings();
  }

  /// Open location settings
  Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }
}
