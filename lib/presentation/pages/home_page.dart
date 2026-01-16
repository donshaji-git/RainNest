import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../providers/location_provider.dart';
import '../../providers/weather_provider.dart';
import '../../providers/station_provider.dart';
import '../../services/location_service.dart';
import '../../data/models/umbrella_location.dart';
import '../../services/weather_service.dart';
import '../widgets/app_bottom_footer.dart';

import 'dart:ui';
import '../../providers/map_provider.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _searchController = TextEditingController();
  List<LatLng> _routePoints = [];
  UmbrellaLocation? _selectedStation;
  bool _firstLocationFixed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialize();
    });
  }

  void _initialize() async {
    final locationProvider = context.read<LocationProvider>();
    final weatherProvider = context.read<WeatherProvider>();
    final stationProvider = context.read<StationProvider>();

    await locationProvider.initialize();

    if (locationProvider.hasLocation) {
      final loc = locationProvider.currentLocation!;
      weatherProvider.fetchWeather(loc);
      stationProvider.initialize(loc);
    } else {
      stationProvider.initialize(null);
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

  void _showStationDetails(UmbrellaLocation station) {
    _fetchDirections(station);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _StationDetailsSheet(station: station),
    );
  }

  void _fetchDirections(UmbrellaLocation station) async {
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

  @override
  Widget build(BuildContext context) {
    final locationProvider = context.watch<LocationProvider>();
    final weatherProvider = context.watch<WeatherProvider>();
    final stationProvider = context.watch<StationProvider>();
    final mapProvider = context.watch<MapProvider>();

    // Update station provider with latest user location
    if (locationProvider.hasLocation) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        stationProvider.updateLocation(locationProvider.currentLocation);

        if (!_firstLocationFixed && locationProvider.currentLocation != null) {
          mapProvider.centerOnUser(locationProvider.currentLocation!);
          _firstLocationFixed = true;

          if (stationProvider.nearestStation != null) {
            _fetchDirections(stationProvider.nearestStation!);
          }
        }
      });
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
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
                _buildHeader(weatherProvider, locationProvider, mapProvider),

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
                          locationProvider.hasLocation)
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
                        onPressed: () {},
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
      ),
      bottomNavigationBar: AppBottomFooter(
        currentIndex: 0,
        onItemSelected: (i) {},
        onScanPressed: () {},
      ),
    );
  }

  Widget _buildHeader(
    WeatherProvider weatherProvider,
    LocationProvider locationProvider,
    MapProvider mapProvider,
  ) {
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
                      weatherProvider.greeting,
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
              if (weatherProvider.hasWeather)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Text(
                        WeatherService.getWeatherIcon(
                          weatherProvider.currentWeather!.condition,
                        ),
                        style: const TextStyle(fontSize: 24),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${weatherProvider.currentWeather!.temperature.toStringAsFixed(0)}°',
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1A1A1A),
                        ),
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
        child: const Center(
          child: CircularProgressIndicator(color: Color(0xFF0066FF)),
        ),
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
            // User Location Marker (Premium Pulse effect)
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
              final isNearest = stationProvider.nearestStation?.id == s.id;
              final isSelected = _selectedStation?.id == s.id;

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
    UmbrellaLocation station,
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
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
          ),
          child: Row(
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
              const SizedBox(width: 15),
              Expanded(
                child: Column(
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
                      station.machineName,
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1A1A1A),
                      ),
                    ),
                    Text(
                      "$distanceText away • ${station.availableUmbrellas} Available",
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
        ),
      ),
    );
  }

  Widget _buildStationList(
    StationProvider stationProvider,
    LocationProvider locationProvider,
  ) {
    if (stationProvider.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF0066FF)),
      );
    }

    if (stationProvider.stations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text(
              "No machines found nearby",
              style: GoogleFonts.outfit(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 5, 20, 20),
      itemCount: stationProvider.stations.length,
      itemBuilder: (context, index) {
        final station = stationProvider.stations[index];
        final isNearest = index == 0;

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

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            ],
            border: isNearest
                ? Border.all(
                    color: const Color(0xFF0066FF).withValues(alpha: 0.3),
                    width: 2,
                  )
                : null,
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            onTap: () => _showStationDetails(station),
            leading: Container(
              width: 55,
              height: 55,
              decoration: BoxDecoration(
                color: isNearest
                    ? const Color(0xFF0066FF).withValues(alpha: 0.1)
                    : Colors.grey[50],
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                Icons.umbrella_rounded,
                color: isNearest ? const Color(0xFF0066FF) : Colors.grey[400],
                size: 28,
              ),
            ),
            title: Text(
              station.machineName,
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: const Color(0xFF1A1A1A),
              ),
            ),
            subtitle: Text(
              station.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(fontSize: 13, color: Colors.grey[600]),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  distanceText,
                  style: GoogleFonts.outfit(
                    color: const Color(0xFF1A1A1A),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "${station.availableUmbrellas} left",
                  style: GoogleFonts.outfit(
                    color: station.availableUmbrellas > 0
                        ? Colors.green
                        : Colors.red,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StationDetailsSheet extends StatelessWidget {
  final UmbrellaLocation station;
  const _StationDetailsSheet({required this.station});

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(40),
            topRight: Radius.circular(40),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 40,
              offset: const Offset(0, -10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 60,
                height: 6,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 30),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        station.machineName,
                        style: GoogleFonts.outfit(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        station.description,
                        style: GoogleFonts.outfit(
                          color: Colors.grey[600],
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0066FF).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.share_rounded,
                    color: Color(0xFF0066FF),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),
            Row(
              children: [
                _buildInfoCard(
                  label: "Available",
                  value: "${station.availableUmbrellas}",
                  icon: Icons.umbrella_rounded,
                  color: Colors.blue,
                ),
                const SizedBox(width: 15),
                _buildInfoCard(
                  label: "Positions",
                  value: "${station.availableReturnSlots}",
                  icon: Icons.move_to_inbox_rounded,
                  color: Colors.teal,
                ),
              ],
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0066FF),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 65),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
                elevation: 10,
                shadowColor: const Color(0xFF0066FF).withValues(alpha: 0.5),
              ),
              child: Text(
                "Close",
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: Colors.grey[100]!),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 12),
            Text(
              value,
              style: GoogleFonts.outfit(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1A1A1A),
              ),
            ),
            Text(
              label,
              style: GoogleFonts.outfit(
                color: Colors.grey,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
