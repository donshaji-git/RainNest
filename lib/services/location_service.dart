import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class SearchResult {
  final String name;
  final LatLng location;

  SearchResult({required this.name, required this.location});
}

enum LocationPermissionState {
  granted,
  denied,
  permanentlyDenied,
  disabled, // Location service (GPS) is off
}

class LocationService {
  /// Checks permissions and GPS service status.
  /// Note: GPS cannot be auto-enabled on Android from the app.
  static Future<LocationPermissionState> checkAndRequestPermission() async {
    // 1. Check if GPS service is enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return LocationPermissionState.disabled;
    }

    // 2. Check and request location permissions
    var status = await Permission.location.status;

    if (status.isDenied) {
      status = await Permission.location.request();
      if (status.isDenied) {
        return LocationPermissionState.denied;
      }
    }

    if (status.isPermanentlyDenied) {
      return LocationPermissionState.permanentlyDenied;
    }

    if (status.isGranted) {
      return LocationPermissionState.granted;
    }

    return LocationPermissionState.denied;
  }

  /// Opens location settings to let the user enable GPS.
  static Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  /// Opens app settings to let the user grant permission.
  static Future<void> openAppSettings() async {
    await Permission.location.request();
    await Geolocator.openAppSettings();
  }

  static Future<Position?> getCurrentPosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      debugPrint('Location Error: $e');
      return null;
    }
  }

  /// Get live position stream with high accuracy.
  static Stream<Position> getPositionStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2, // Update every 2 meters for smoothness
      ),
    );
  }

  /// Calculate distance between two points in meters using Haversine formula.
  static double calculateHaversineDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
  }

  static Future<List<SearchResult>> searchPlaces(String query) async {
    if (query.isEmpty) return [];

    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/search?q=$query&format=json&limit=5',
    );

    try {
      final response = await http.get(
        url,
        headers: {'User-Agent': 'RainNest-Consumer-App'},
      );

      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        return data.map((item) {
          return SearchResult(
            name: item['display_name'],
            location: LatLng(
              double.parse(item['lat']),
              double.parse(item['lon']),
            ),
          );
        }).toList();
      }
    } catch (e) {
      debugPrint('Search Error: $e');
    }
    return [];
  }

  /// Get routing directions using OSRM
  static Future<List<LatLng>> getRoute(LatLng start, LatLng end) async {
    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=geojson',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List coordinates = data['routes'][0]['geometry']['coordinates'];
        return coordinates.map((c) => LatLng(c[1], c[0])).toList();
      } else {
        debugPrint('OSRM Error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('OSRM Error: $e');
    }
    return [];
  }
}
