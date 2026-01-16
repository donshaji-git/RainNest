import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:provider/provider.dart';
import '../../data/models/umbrella_location.dart';
import '../../services/database_service.dart';
import '../../services/location_service.dart';
import '../constants/admin_constants.dart';
import '../../providers/location_provider.dart';
import '../../providers/map_provider.dart';
import 'dart:ui';

class UmbrellaMapPage extends StatefulWidget {
  const UmbrellaMapPage({super.key});

  @override
  State<UmbrellaMapPage> createState() => _UmbrellaMapPageState();
}

class _UmbrellaMapPageState extends State<UmbrellaMapPage> {
  final DatabaseService _db = DatabaseService();
  bool _isAdmin = false;
  bool _firstLocationFixed = false;

  @override
  void initState() {
    super.initState();
    _checkAdminStatus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LocationProvider>().initialize();
    });
  }

  void _checkAdminStatus() {
    final user = FirebaseAuth.instance.currentUser;
    setState(() {
      _isAdmin = AdminConstants.isAdmin(user?.email);
    });
  }

  void _logout() async {
    await FirebaseAuth.instance.signOut();
  }

  void _manageMachine({
    LatLng? point,
    UmbrellaLocation? existingMachine,
  }) async {
    if (!_isAdmin) return;

    final nameController = TextEditingController(
      text: existingMachine?.machineName,
    );
    final descController = TextEditingController(
      text: existingMachine?.description,
    );
    final slotCountController = TextEditingController(
      text: existingMachine != null
          ? existingMachine.totalSlots.toString()
          : "",
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existingMachine == null ? "Add Machine" : "Edit Machine"),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: "Machine Name"),
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
                decoration: const InputDecoration(labelText: "Number of Slots"),
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
                  slotCountController.text.isEmpty)
                return;
              final totalSlots = int.tryParse(slotCountController.text) ?? 0;
              final slotIds = List.generate(
                totalSlots,
                (index) => "S${index + 1}",
              );

              final machine = UmbrellaLocation(
                id: existingMachine?.id ?? '',
                machineName: nameController.text,
                description: descController.text,
                latitude: existingMachine?.latitude ?? point!.latitude,
                longitude: existingMachine?.longitude ?? point!.longitude,
                totalSlots: totalSlots,
                availableUmbrellas:
                    existingMachine?.availableUmbrellas ?? totalSlots,
                availableReturnSlots:
                    existingMachine?.availableReturnSlots ?? 0,
                slotIds: slotIds,
                createdAt: existingMachine?.createdAt ?? DateTime.now(),
              );

              final navigator = Navigator.of(context);
              try {
                if (existingMachine == null) {
                  await _db.addUmbrellaLocation(machine);
                } else {
                  await _db.updateUmbrellaLocation(machine);
                }
                navigator.pop();
              } catch (e) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text("Error: $e")));
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0066FF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(existingMachine == null ? "Add" : "Save"),
          ),
        ],
      ),
    );
  }

  void _showLocationDetails(UmbrellaLocation loc) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
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
                          loc.machineName,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          loc.description,
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
                            _manageMachine(existingMachine: loc);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () {
                            Navigator.pop(context);
                            _deleteLocation(loc);
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
                      "Total Slots: ${loc.totalSlots}",
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
                  itemCount: loc.slotIds.length,
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
                        loc.slotIds[index],
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

  void _deleteLocation(UmbrellaLocation location) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Machine"),
        content: Text(
          "Are you sure you want to delete '${location.machineName}'?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              await _db.deleteUmbrellaLocation(location.id);
              if (mounted) Navigator.pop(context);
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

    if (locationProvider.hasLocation && !_firstLocationFixed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        mapProvider.centerOnUser(locationProvider.currentLocation!);
        _firstLocationFixed = true;
      });
    }

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
    return StreamBuilder<List<UmbrellaLocation>>(
      stream: _db.getUmbrellaLocations(),
      builder: (context, snapshot) {
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
                              color: Colors.black26,
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
