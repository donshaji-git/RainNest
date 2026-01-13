import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/database_service.dart';
import '../../services/location_service.dart';
import '../../services/weather_service.dart';
import '../../services/notification_service.dart';
import '../../data/models/user_model.dart';
import '../../data/models/umbrella_location.dart';
import '../../data/models/weather_models.dart';
import '../widgets/home_widgets.dart';
import '../widgets/app_bottom_footer.dart';
import 'user_map_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final DatabaseService _db = DatabaseService();

  UserModel? _userProfile;
  WeatherData? _weather;
  List<UmbrellaLocation> _machines = [];
  LatLng? _currentLocation;
  LocationPermissionState _locationState = LocationPermissionState.denied;
  bool _isLoading = true;
  bool _hasTriggeredRainAlert = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await NotificationService.requestPermissions();
    await _loadUserProfile();
    await _checkLocation();
    _setupStationStream();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final profile = await _db.getUser(user.uid);
      if (mounted) setState(() => _userProfile = profile);
    }
  }

  Future<void> _checkLocation() async {
    final state = await LocationService.checkAndRequestPermission();
    if (mounted) setState(() => _locationState = state);

    if (state == LocationPermissionState.granted) {
      final pos = await LocationService.getCurrentPosition();
      if (pos != null) {
        final latLng = LatLng(pos.latitude, pos.longitude);
        if (mounted) setState(() => _currentLocation = latLng);
        _loadWeather(latLng);
      }
    } else if (state == LocationPermissionState.disabled ||
        state == LocationPermissionState.denied ||
        state == LocationPermissionState.permanentlyDenied) {
      if (mounted) _showLocationPermissionDialog();
    }
  }

  void _showLocationPermissionDialog() {
    String title = 'Location Access';
    String content =
        'RainNest needs your location to find nearby kiosks and show weather alerts.';
    String buttonText = 'Grant Access';

    if (_locationState == LocationPermissionState.disabled) {
      title = 'GPS is Off';
      content =
          'Please enable Location Services (GPS) in your phone settings to use RainNest.';
      buttonText = 'Open Settings';
    } else if (_locationState == LocationPermissionState.permanentlyDenied) {
      title = 'Permission Denied';
      content =
          'Location permission is permanently denied. Please enable it in App Settings.';
      buttonText = 'App Settings';
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              if (_locationState == LocationPermissionState.disabled) {
                await LocationService.openLocationSettings();
              } else if (_locationState ==
                  LocationPermissionState.permanentlyDenied) {
                await LocationService.openAppSettings();
              } else {
                await _checkLocation();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0066FF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(buttonText),
          ),
        ],
      ),
    );
  }

  Future<void> _loadWeather(LatLng loc) async {
    final weather = await WeatherService.fetchWeather(
      loc.latitude,
      loc.longitude,
    );
    if (mounted) {
      setState(() => _weather = weather);
      if (weather != null && weather.hasRainAlert && !_hasTriggeredRainAlert) {
        NotificationService.sendRainAlert();
        _hasTriggeredRainAlert = true;
      }
    }
  }

  void _setupStationStream() {
    _db.getUmbrellaLocations().listen((data) {
      if (mounted) {
        if (_currentLocation != null) {
          data.sort((a, b) {
            final distA = Geolocator.distanceBetween(
              _currentLocation!.latitude,
              _currentLocation!.longitude,
              a.latitude,
              a.longitude,
            );
            final distB = Geolocator.distanceBetween(
              _currentLocation!.latitude,
              _currentLocation!.longitude,
              b.latitude,
              b.longitude,
            );
            return distA.compareTo(distB);
          });
        }
        setState(() => _machines = data);
      }
    });
  }

  void _showMachineDetails(UmbrellaLocation loc) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _MachineDetailsSheet(location: loc, userLocation: _currentLocation),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF0066FF)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: RefreshIndicator(
        onRefresh: _initialize,
        color: const Color(0xFF0066FF),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 40),
                child: HomeHeader(username: _userProfile?.name ?? 'User'),
              ),
            ),
            SliverToBoxAdapter(
              child: WeatherAlertCard(
                weather: _weather,
                onViewMap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const UserMapPage(),
                    ),
                  );
                },
              ),
            ),
            SliverToBoxAdapter(
              child: NearbyNestsSection(
                machines: _machines,
                userLocation: _currentLocation,
                onKioskTapped: _showMachineDetails,
              ),
            ),
            SliverToBoxAdapter(
              child: AvailabilityGrid(
                umbrellas: _machines.fold(
                  0,
                  (sum, m) => sum + m.availableUmbrellas,
                ),
                slots: _machines.fold(
                  0,
                  (sum, m) => sum + m.availableReturnSlots,
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomFooter(
        currentIndex: 0,
        onItemSelected: (index) {},
        onScanPressed: () {},
      ),
    );
  }
}

class _MachineDetailsSheet extends StatelessWidget {
  final UmbrellaLocation location;
  final LatLng? userLocation;

  const _MachineDetailsSheet({required this.location, this.userLocation});

  @override
  Widget build(BuildContext context) {
    final distance = userLocation != null
        ? Geolocator.distanceBetween(
            userLocation!.latitude,
            userLocation!.longitude,
            location.latitude,
            location.longitude,
          )
        : null;

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(40),
          topRight: Radius.circular(40),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 50,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            location.machineName,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          Text(
            location.description,
            style: TextStyle(color: Colors.grey[600], fontSize: 16),
          ),
          if (distance != null)
            Text(
              '${(distance / 1000).toStringAsFixed(1)} km away',
              style: const TextStyle(
                color: Color(0xFF0066FF),
                fontWeight: FontWeight.bold,
              ),
            ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildInfo('Available', location.availableUmbrellas.toString()),
              _buildInfo(
                'Return Slots',
                location.availableReturnSlots.toString(),
              ),
              _buildInfo('Total', location.totalSlots.toString()),
            ],
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0066FF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: const Text('Close', style: TextStyle(fontSize: 18)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfo(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 14)),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
