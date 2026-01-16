import 'dart:async';
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
  StreamSubscription<Position>? _positionSubscription;

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
        // Start listening to live updates immediately
        _startLocationStream();

        // Get initial position with timeout
        try {
          final position = await LocationService.getCurrentPosition().timeout(
            const Duration(seconds: 5),
          );
          if (position != null) {
            _currentLocation = LatLng(position.latitude, position.longitude);
            notifyListeners();
          }
        } catch (e) {
          debugPrint('Initial position fetch timed out: $e');
        }
      } else if (state == LocationPermissionState.disabled) {
        _isServiceEnabled = false;
        _errorMessage = 'Location service is disabled. Opening settings...';
        await LocationService.openLocationSettings();
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

  void _startLocationStream() {
    _positionSubscription?.cancel();
    _positionSubscription = LocationService.getPositionStream().listen(
      (position) {
        _currentLocation = LatLng(position.latitude, position.longitude);
        _errorMessage = null;
        _isServiceEnabled = true;
        notifyListeners();
      },
      onError: (error) {
        _errorMessage = 'Location stream error: $error';
        notifyListeners();
      },
    );
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
        _startLocationStream(); // Ensure stream is running
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

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }
}
