import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/location_service.dart';
import '../../services/database_service.dart';
import '../../data/models/umbrella_location.dart';

class UserMapPage extends StatefulWidget {
  const UserMapPage({super.key});

  @override
  State<UserMapPage> createState() => _UserMapPageState();
}

class _UserMapPageState extends State<UserMapPage> {
  final MapController _mapController = MapController();
  final DatabaseService _db = DatabaseService();
  LatLng? _userLocation;
  List<UmbrellaLocation> _stations = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final pos = await LocationService.getCurrentPosition();
      if (pos != null) {
        setState(() => _userLocation = LatLng(pos.latitude, pos.longitude));
      }

      // Load stations
      _db.getUmbrellaLocations().listen((stations) {
        if (mounted) {
          setState(() {
            _stations = stations;
            _isLoading = false;
          });
        }
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showStationDetails(UmbrellaLocation station) {
    double? distance;
    if (_userLocation != null) {
      distance = Geolocator.distanceBetween(
        _userLocation!.latitude,
        _userLocation!.longitude,
        station.latitude,
        station.longitude,
      );
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      station.machineName,
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (distance != null)
                      Text(
                        '${(distance / 1000).toStringAsFixed(1)} km away',
                        style: GoogleFonts.inter(color: Colors.grey[600]),
                      ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Available',
                    style: GoogleFonts.inter(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              station.description,
              style: GoogleFonts.inter(color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                _buildInfoItem(
                  Icons.umbrella,
                  '${station.availableUmbrellas}',
                  'Available',
                ),
                const SizedBox(width: 16),
                _buildInfoItem(
                  Icons.grid_view_rounded,
                  '${station.availableReturnSlots}',
                  'Return Slots',
                ),
              ],
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0066FF),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              child: const Text('Get Directions'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFF0066FF)),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              label,
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _userLocation ?? const LatLng(10.0, 76.0),
              initialZoom: 13,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.rainnest',
              ),
              MarkerLayer(
                markers: [
                  if (_userLocation != null)
                    Marker(
                      point: _userLocation!,
                      child: const CircleAvatar(
                        backgroundColor: Colors.white,
                        radius: 10,
                        child: CircleAvatar(
                          backgroundColor: Color(0xFF0066FF),
                          radius: 7,
                        ),
                      ),
                    ),
                  ..._stations.map(
                    (station) => Marker(
                      point: LatLng(station.latitude, station.longitude),
                      width: 40,
                      height: 40,
                      child: GestureDetector(
                        onTap: () => _showStationDetails(station),
                        child: const Icon(
                          Icons.location_on,
                          color: Color(0xFF0066FF),
                          size: 40,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            top: 50,
            left: 20,
            child: CircleAvatar(
              backgroundColor: Colors.white,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
          if (_isLoading) const Center(child: CircularProgressIndicator()),
          Positioned(
            bottom: 30,
            right: 20,
            child: FloatingActionButton(
              backgroundColor: Colors.white,
              onPressed: () {
                if (_userLocation != null) {
                  _mapController.move(_userLocation!, 15);
                }
              },
              child: const Icon(Icons.my_location, color: Color(0xFF0066FF)),
            ),
          ),
        ],
      ),
    );
  }
}
