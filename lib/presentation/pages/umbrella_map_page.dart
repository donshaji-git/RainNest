import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:provider/provider.dart';
import '../../data/models/station.dart';
import '../../data/models/umbrella.dart';
import '../../services/database_service.dart';
import '../../services/auth_service.dart';
import '../../services/location_service.dart';
import '../constants/admin_constants.dart';
import '../../providers/location_provider.dart';
import '../../providers/map_provider.dart';
import 'dart:ui';
import '../widgets/rain_nest_loader.dart';

class UmbrellaMapPage extends StatefulWidget {
  const UmbrellaMapPage({super.key});

  @override
  State<UmbrellaMapPage> createState() => _UmbrellaMapPageState();
}

class _UmbrellaMapPageState extends State<UmbrellaMapPage> {
  final DatabaseService _db = DatabaseService();
  bool _isAdmin = false;
  bool _firstLocationFixed = false;
  LocationProvider? _locationProvider;

  @override
  void initState() {
    super.initState();
    _checkAdminStatus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialize();
    });
  }

  void _onLocationChanged() {
    if (!mounted) return;
    final locationProvider = context.read<LocationProvider>();
    final mapProvider = context.read<MapProvider>();

    if (locationProvider.hasLocation && !_firstLocationFixed) {
      mapProvider.centerOnUser(locationProvider.currentLocation!);
      _firstLocationFixed = true;
    }
  }

  void _initialize() async {
    _locationProvider = context.read<LocationProvider>();

    // Add listener for future updates
    _locationProvider?.addListener(_onLocationChanged);

    await _locationProvider?.initialize();

    // Check initial state
    if (_locationProvider?.hasLocation ?? false) {
      _onLocationChanged();
    }
  }

  @override
  void dispose() {
    _locationProvider?.removeListener(_onLocationChanged);
    super.dispose();
  }

  void _checkAdminStatus() {
    final user = FirebaseAuth.instance.currentUser;
    setState(() {
      _isAdmin = AdminConstants.isAdmin(user?.email);
    });
  }

  void _logout() async {
    await AuthService().signOut();
  }

  void _manageMachine({LatLng? point, Station? existingStation}) async {
    if (!_isAdmin) return;

    final nameController = TextEditingController(text: existingStation?.name);
    final descController = TextEditingController(
      text: existingStation?.description,
    );
    final slotCountController = TextEditingController(
      text: existingStation != null
          ? existingStation.totalSlots.toString()
          : "",
    );

    // Track umbrella IDs for initial queue
    final queueController = TextEditingController(
      text: existingStation?.queueOrder.join(",") ?? "",
    );
    final qrController = TextEditingController(
      text: existingStation?.machineQrCode ?? "",
    );

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                existingStation == null ? "Add Machine" : "Edit Machine",
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: "Machine Name",
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: qrController,
                      decoration: const InputDecoration(
                        labelText: "Machine QR ID",
                        hintText: "M_001",
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descController,
                      decoration: const InputDecoration(
                        labelText: "Landmark / Building",
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: slotCountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "Number of Slots",
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: queueController,
                      decoration: const InputDecoration(
                        labelText: "Umbrella IDs (Comma separated, FIFO order)",
                        hintText: "U1,U2,U3",
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (nameController.text.isEmpty ||
                        slotCountController.text.isEmpty ||
                        qrController.text.isEmpty) {
                      return;
                    }
                    final totalSlots =
                        int.tryParse(slotCountController.text) ?? 0;
                    final queue = queueController.text
                        .split(",")
                        .map((e) => e.trim())
                        .where((e) => e.isNotEmpty)
                        .toList();

                    final station = Station(
                      stationId: existingStation?.stationId ?? '',
                      name: nameController.text,
                      description: descController.text,
                      latitude: existingStation?.latitude ?? point!.latitude,
                      longitude: existingStation?.longitude ?? point!.longitude,
                      totalSlots: totalSlots,
                      availableCount: queue.length,
                      freeSlotsCount: totalSlots - queue.length,
                      queueOrder: queue,
                      machineQrCode: qrController.text,
                    );

                    final navigator = Navigator.of(context);
                    try {
                      if (existingStation == null) {
                        await _db.addStation(station);
                      } else {
                        await _db.updateStation(station);
                      }

                      // Update/Create Umbrella table entries
                      for (var umbrellaId in queue) {
                        await _db.saveUmbrella(
                          Umbrella(
                            umbrellaId: umbrellaId,
                            stationId: station.stationId,
                            status: 'available',
                            createdAt: DateTime.now(),
                          ),
                        );
                      }

                      navigator.pop();
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text("Error: $e")));
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0066FF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(existingStation == null ? "Add" : "Save"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showLocationDetails(Station station) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(230),
            borderRadius: const BorderRadius.only(
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
                          station.name,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          station.description,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_isAdmin)
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.edit,
                            color: Color(0xFF0066FF),
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                            _manageMachine(existingStation: station);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () {
                            Navigator.pop(context);
                            _deleteLocation(station);
                          },
                        ),
                      ],
                    ),
                ],
              ),
              const Divider(height: 40),
              Text(
                "MANAGEMENT OVERVIEW",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[400],
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF0066FF).withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.grid_view_rounded,
                      color: Color(0xFF0066FF),
                      size: 30,
                    ),
                    const SizedBox(width: 15),
                    Text(
                      "Total Slots: ${station.totalSlots}",
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0066FF),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 25),
              SizedBox(
                height: 45,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: station.queueOrder.length,
                  itemBuilder: (context, index) => Container(
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[100]!),
                    ),
                    child: Center(
                      child: Text(
                        station.queueOrder[index],
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _deleteLocation(Station station) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Machine"),
        content: Text("Are you sure you want to delete '${station.name}'?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              await _db.deleteStation(station.stationId);
              if (context.mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locationProvider = context.watch<LocationProvider>();
    final mapProvider = context.watch<MapProvider>();

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // Premium Admin Header
          _buildHeader(mapProvider),

          // Map Section
          Expanded(
            flex: 5,
            child: Container(
              margin: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(35),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 30,
                    offset: const Offset(0, 15),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(35),
                child: Stack(
                  children: [
                    _buildMap(locationProvider, mapProvider),
                    // Floating Admin Tooltip
                    Positioned(
                      top: 20,
                      right: 20,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(color: Colors.black12, blurRadius: 10),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.touch_app_rounded,
                              size: 16,
                              color: Color(0xFF0066FF),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              "Tap map to add machine",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[700],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Branding Footer
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Text(
              "RainNest Infrastructure Management",
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(MapProvider mapProvider) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 10,
        bottom: 25,
        left: 24,
        right: 24,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0066FF), Color(0xFF00B2FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(40),
          bottomRight: Radius.circular(40),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Admin Terminal",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Text(
                    "Infrastructure Overview",
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.logout_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                onPressed: _logout,
              ),
            ],
          ),
          const SizedBox(height: 20),
          TypeAheadField<SearchResult>(
            builder: (context, controller, focusNode) => Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 15)],
              ),
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                decoration: InputDecoration(
                  hintText: "Search Building / College",
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
              title: Text(
                suggestion.name,
                style: const TextStyle(fontSize: 14),
              ),
              leading: const Icon(
                Icons.location_on_rounded,
                color: Color(0xFF0066FF),
                size: 20,
              ),
            ),
            onSelected: (suggestion) {
              mapProvider.moveTo(suggestion.location, 16.0);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMap(LocationProvider locationProvider, MapProvider mapProvider) {
    return StreamBuilder<List<Station>>(
      stream: _db.getStationsStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Stream Error: ${snapshot.error}'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: RainNestLoader(color: Color(0xFF0066FF)));
        }

        final locations = snapshot.data ?? [];
        return FlutterMap(
          mapController: mapProvider.mapController,
          options: MapOptions(
            initialCenter:
                locationProvider.currentLocation ??
                const LatLng(9.9312, 76.2673),
            initialZoom: 14,
            onTap: (tapPosition, point) => _manageMachine(point: point),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.rainnest',
            ),
            MarkerLayer(
              markers: [
                // User Location (Admin Dot)
                if (locationProvider.currentLocation != null)
                  Marker(
                    point: locationProvider.currentLocation!,
                    width: 50,
                    height: 50,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF0066FF,
                            ).withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                        ),
                        Container(
                          width: 14,
                          height: 14,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: Colors.black26, blurRadius: 4),
                            ],
                          ),
                          child: Center(
                            child: Container(
                              width: 10,
                              height: 10,
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
                // Machine Markers
                ...locations.map(
                  (loc) => Marker(
                    point: LatLng(loc.latitude, loc.longitude),
                    width: 50,
                    height: 50,
                    child: GestureDetector(
                      onTap: () => _showLocationDetails(loc),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.26),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                          border: Border.all(
                            color: const Color(0xFF0066FF),
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.umbrella_rounded,
                          color: Color(0xFF0066FF),
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
