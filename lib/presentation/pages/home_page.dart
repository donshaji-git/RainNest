import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../providers/location_provider.dart';
import '../../providers/station_provider.dart';
import '../../services/location_service.dart';
import '../../services/database_service.dart';
import '../../data/models/station.dart';
import '../widgets/app_bottom_footer.dart';
import '../widgets/rain_nest_loader.dart';
import '../../providers/user_provider.dart';

import 'dart:ui';
import '../../providers/map_provider.dart';
import 'profile_page.dart';
import 'wallet_page.dart';
import 'scanner_page.dart';
import '../../providers/rental_provider.dart';
import 'umbrella_page.dart';
import '../../data/models/user_model.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _searchController = TextEditingController();
  List<LatLng> _routePoints = [];
  Station? _selectedStation;
  bool _firstLocationFixed = false;
  bool _showRecommendation = true;
  int _currentIndex = 0;
  LocationProvider? _locationProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialize();
    });
  }

  void _onLocationChanged() {
    if (!mounted) return;
    final locationProvider = context.read<LocationProvider>();
    final stationProvider = context.read<StationProvider>();
    final mapProvider = context.read<MapProvider>();

    if (locationProvider.hasLocation) {
      final loc = locationProvider.currentLocation!;

      // Update other providers
      stationProvider.updateLocation(loc);

      // Center map on first fix
      if (!_firstLocationFixed) {
        mapProvider.centerOnUser(loc);
        _firstLocationFixed = true;

        // Fetch initial direction
        if (stationProvider.nearestStation != null) {
          _fetchDirections(stationProvider.nearestStation!);
        }
      }
    }
  }

  @override
  void dispose() {
    _locationProvider?.removeListener(_onLocationChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _initialize() async {
    _locationProvider = context.read<LocationProvider>();
    final stationProvider = context.read<StationProvider>();

    // 1. Start station listener immediately (with null location initially)
    stationProvider.initialize(_locationProvider?.currentLocation);

    // 2. Add listener for future location updates
    _locationProvider?.addListener(_onLocationChanged);

    // 3. Request location fix
    await _locationProvider?.initialize();

    // 4. If we have location already, sync everything
    if (_locationProvider?.hasLocation ?? false) {
      final loc = _locationProvider!.currentLocation!;
      stationProvider.updateLocation(loc);

      if (!_firstLocationFixed) {
        if (!mounted) return;
        context.read<MapProvider>().centerOnUser(loc);
        _firstLocationFixed = true;
      }
    }
  }

  void _onSearch(String query) async {
    final stationProvider = context.read<StationProvider>();
    final mapProvider = context.read<MapProvider>();
    final location = await stationProvider.searchLocation(query);
    if (location != null) {
      mapProvider.moveTo(location, 16);
    }
  }

  void _retryLocation() {
    context.read<LocationProvider>().initialize();
  }

  void _showStationDetails(Station station) {
    _fetchDirections(station);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _StationDetailsSheet(
        station: station,
        onRouteRequested: () => _fetchDirections(station),
        onRentRequested: () {
          context.read<RentalProvider>().setTargetStation(station);
          setState(() {
            _currentIndex = 2; // Switch to Scanner Tab
          });
        },
      ),
    );
  }

  void _fetchDirections(Station station) async {
    final userLoc = context.read<LocationProvider>().currentLocation;
    if (userLoc == null) return;

    setState(() {
      _selectedStation = station;
      _routePoints = [];
    });

    final points = await LocationService.getRoute(
      userLoc,
      LatLng(station.latitude, station.longitude),
    );

    if (mounted) {
      setState(() {
        _routePoints = points;
      });
      if (points.isNotEmpty) {
        context.read<MapProvider>().moveTo(
          LatLng(station.latitude, station.longitude),
          15,
        );
      }
    }
  }

  void _showAllStations(
    StationProvider stationProvider,
    LocationProvider locationProvider,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(35),
            topRight: Radius.circular(35),
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              "All Stations",
              style: GoogleFonts.outfit(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: _buildStationList(stationProvider, locationProvider),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildHomeBody(),
          const UmbrellaPage(),
          const ScannerPage(),
          const WalletPage(),
          const ProfilePage(),
        ],
      ),
      bottomNavigationBar: AppBottomFooter(
        currentIndex: _currentIndex,
        onItemSelected: (i) {
          setState(() {
            _currentIndex = i;
          });
        },
      ),
    );
  }

  Widget _buildHomeBody() {
    final locationProvider = context.watch<LocationProvider>();

    final stationProvider = context.watch<StationProvider>();
    final mapProvider = context.watch<MapProvider>();

    return Stack(
      children: [
        // Background Gradient to match premium feel
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFF0F7FF), Colors.white],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ),

        SafeArea(
          child: Column(
            children: [
              // 1. Premium Header
              _buildHeader(locationProvider, mapProvider),

              // 2. Map Section with Floating Card
              Expanded(
                child: Stack(
                  children: [
                    // Map Container
                    Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(35),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF0066FF,
                            ).withValues(alpha: 0.1),
                            blurRadius: 30,
                            offset: const Offset(0, 15),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(35),
                        child: _buildMap(
                          locationProvider,
                          stationProvider,
                          mapProvider,
                        ),
                      ),
                    ),

                    // Floating Recommendation Card
                    if (stationProvider.nearestStation != null &&
                        locationProvider.hasLocation &&
                        _showRecommendation)
                      Positioned(
                        bottom: 25,
                        left: 35,
                        right: 35,
                        child: _buildRecommendationCard(
                          stationProvider.nearestStation!,
                          locationProvider,
                        ),
                      ),
                  ],
                ),
              ),

              // 3. Station List Title
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Nearby Stations",
                      style: GoogleFonts.outfit(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1A1A1A),
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          _showAllStations(stationProvider, locationProvider),
                      child: Text(
                        "View All",
                        style: GoogleFonts.outfit(
                          color: const Color(0xFF0066FF),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 4. Station List (Glassmorphism inspired items)
              Expanded(
                child: _buildStationList(stationProvider, locationProvider),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(
    LocationProvider locationProvider,
    MapProvider mapProvider,
  ) {
    String greeting = "Good Day!";
    final hour = DateTime.now().hour;
    if (hour < 12) {
      greeting = "Good Morning!";
    } else if (hour < 17) {
      greeting = "Good Afternoon!";
    } else {
      greeting = "Good Evening!";
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 20),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      greeting,
                      style: GoogleFonts.outfit(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1A1A1A),
                      ).copyWith(letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_rounded,
                          size: 14,
                          color: Color(0xFF0066FF),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          locationProvider.hasLocation
                              ? "Live Tracking Active"
                              : "Waiting for location...",
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Search Bar
          TypeAheadField<SearchResult>(
            builder: (context, controller, focusNode) => Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                onSubmitted: _onSearch,
                style: GoogleFonts.outfit(),
                decoration: InputDecoration(
                  hintText: "Search Building / College",
                  hintStyle: GoogleFonts.outfit(color: Colors.grey[400]),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: Color(0xFF0066FF),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ),
            suggestionsCallback: (pattern) =>
                LocationService.searchPlaces(pattern),
            itemBuilder: (context, suggestion) => ListTile(
              leading: const Icon(
                Icons.location_on_rounded,
                color: Color(0xFF0066FF),
              ),
              title: Text(
                suggestion.name,
                style: GoogleFonts.outfit(fontSize: 14),
              ),
            ),
            onSelected: (suggestion) {
              _searchController.text = suggestion.name;
              mapProvider.moveTo(suggestion.location, 16);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMap(
    LocationProvider locationProvider,
    StationProvider stationProvider,
    MapProvider mapProvider,
  ) {
    if (locationProvider.isLoading && !locationProvider.hasLocation) {
      return Container(
        color: Colors.grey[100],
        child: const Center(child: RainNestLoader()),
      );
    }

    if (locationProvider.errorMessage != null &&
        !locationProvider.hasLocation) {
      return Container(
        color: Colors.grey[50],
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.location_off_rounded,
                size: 64,
                color: Colors.grey[300],
              ),
              const SizedBox(height: 16),
              Text(
                locationProvider.errorMessage!,
                style: GoogleFonts.outfit(color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _retryLocation,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0066FF),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: const Text("Retry Connection"),
              ),
            ],
          ),
        ),
      );
    }

    return FlutterMap(
      mapController: mapProvider.mapController,
      options: MapOptions(
        initialCenter:
            locationProvider.currentLocation ??
            const LatLng(9.9312, 76.2673), // Kochi default
        initialZoom: 14,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.rainnest',
          tileBuilder: (context, tileWidget, tile) {
            return ColorFiltered(
              colorFilter: ColorFilter.mode(
                Colors.blue.withValues(alpha: 0.05),
                BlendMode.srcATop,
              ),
              child: tileWidget,
            );
          },
        ),
        if (_routePoints.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _routePoints,
                color: const Color(0xFF0066FF),
                strokeWidth: 5,
                borderColor: Colors.white,
                borderStrokeWidth: 2,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            // User Location Marker
            if (locationProvider.currentLocation != null)
              Marker(
                point: locationProvider.currentLocation!,
                width: 60,
                height: 60,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0066FF).withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                    ),
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 5,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                            color: Color(0xFF0066FF),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // Station Markers
            ...stationProvider.stations.map((s) {
              final isNearest =
                  stationProvider.nearestStation?.stationId == s.stationId;
              final isSelected = _selectedStation?.stationId == s.stationId;

              return Marker(
                point: LatLng(s.latitude, s.longitude),
                width: isNearest ? 60 : 45,
                height: isNearest ? 60 : 45,
                child: GestureDetector(
                  onTap: () => _showStationDetails(s),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isNearest
                          ? const Color(0xFF0066FF)
                          : (isSelected ? Colors.orange : Colors.white),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: Icon(
                      Icons.umbrella_rounded,
                      color: isNearest
                          ? Colors.white
                          : (isSelected
                                ? Colors.white
                                : const Color(0xFF0066FF)),
                      size: isNearest ? 30 : 24,
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ],
    );
  }

  Widget _buildRecommendationCard(
    Station station,
    LocationProvider locationProvider,
  ) {
    String distanceText = "";
    if (locationProvider.currentLocation != null) {
      final distMeters = LocationService.calculateHaversineDistance(
        locationProvider.currentLocation!.latitude,
        locationProvider.currentLocation!.longitude,
        station.latitude,
        station.longitude,
      );
      distanceText = distMeters > 1000
          ? "${(distMeters / 1000).toStringAsFixed(1)} km"
          : "${distMeters.toStringAsFixed(0)} m";
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(25),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 10, 20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
          ),
          child: Stack(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0066FF).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(
                      Icons.stars_rounded,
                      color: Color(0xFF0066FF),
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0066FF),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            "NEAREST RENTING MACHINE",
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          station.name,
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1A1A1A),
                          ),
                        ),
                        Text(
                          "$distanceText away • ${station.availableCount} Available",
                          style: GoogleFonts.outfit(
                            color: Colors.grey[600],
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _showStationDetails(station),
                    icon: const Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: Color(0xFF0066FF),
                      size: 20,
                    ),
                  ),
                ],
              ),
              Positioned(
                top: -12,
                right: -6,
                child: IconButton(
                  onPressed: () {
                    setState(() {
                      _showRecommendation = false;
                    });
                  },
                  icon: Icon(
                    Icons.close_rounded,
                    color: Colors.grey[400],
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStationList(
    StationProvider stationProvider,
    LocationProvider locationProvider,
  ) {
    if (stationProvider.isLoading) {
      return const Center(child: RainNestLoader());
    }

    if (stationProvider.stations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.umbrella_rounded, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              "No stations found nearby",
              style: GoogleFonts.outfit(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: stationProvider.stations.length,
      itemBuilder: (context, index) {
        final s = stationProvider.stations[index];
        final distance = locationProvider.currentLocation != null
            ? LocationService.calculateHaversineDistance(
                locationProvider.currentLocation!.latitude,
                locationProvider.currentLocation!.longitude,
                s.latitude,
                s.longitude,
              )
            : null;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0066FF).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(
                Icons.umbrella_rounded,
                color: Color(0xFF0066FF),
              ),
            ),
            title: Text(
              s.name,
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            subtitle: Text(
              "${distance != null ? (distance < 1000 ? "${distance.toStringAsFixed(0)}m" : "${(distance / 1000).toStringAsFixed(1)}km") : ""} • ${s.availableCount} available",
              style: GoogleFonts.outfit(color: Colors.grey[600], fontSize: 13),
            ),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            onTap: () => _showStationDetails(s),
          ),
        );
      },
    );
  }
}

class _StationDetailsSheet extends StatelessWidget {
  final Station station;
  final VoidCallback? onRouteRequested;
  final VoidCallback? onRentRequested;

  const _StationDetailsSheet({
    required this.station,
    this.onRouteRequested,
    this.onRentRequested,
  });

  @override
  Widget build(BuildContext context) {
    // Listen to provider to get real-time updates for this specific station
    final stationProvider = context.watch<StationProvider>();
    final liveStation = stationProvider.stations.firstWhere(
      (s) => s.stationId == station.stationId,
      orElse: () => station,
    );

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(35),
          topRight: Radius.circular(35),
        ),
      ),
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      liveStation.name,
                      style: GoogleFonts.outfit(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      liveStation.description,
                      style: GoogleFonts.outfit(
                        color: Colors.grey[600],
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: () {
                  Navigator.pop(context); // Close sheet
                  if (onRouteRequested != null) {
                    onRouteRequested!();
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0066FF).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.navigation_rounded,
                    color: Color(0xFF0066FF),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _buildInfoCard(
                  "Available",
                  "${liveStation.availableCount}",
                  Icons.umbrella_rounded,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildInfoCard(
                  "Return Slots",
                  "${liveStation.freeSlotsCount}",
                  Icons.move_to_inbox_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const SizedBox(height: 16),
          // Simple Rent Button instead of Grid
          StreamBuilder<UserModel?>(
            stream: DatabaseService().getUserStream(
              context.read<UserProvider>().user?.uid ?? '',
            ),
            builder: (context, userSnapshot) {
              final user = userSnapshot.data;

              return SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: liveStation.availableCount > 0
                      ? () {
                          Navigator.pop(context); // Close sheet
                          if (onRentRequested != null) {
                            onRentRequested!();
                          }
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0066FF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    liveStation.availableCount > 0
                        ? (user != null && user.walletBalance >= 110.0
                              ? "Rent Umbrella (₹10)"
                              : "Pay & Rent (₹${(110.0 - (user?.walletBalance ?? 0.0)).clamp(10.0, 110.0).toStringAsFixed(0)})")
                        : "No Umbrellas Available",
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0066FF).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF0066FF), size: 24),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1A1A1A),
            ),
          ),
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 13,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
