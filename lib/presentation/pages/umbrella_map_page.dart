import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import '../../data/models/umbrella_location.dart';
import '../../services/database_service.dart';
import '../../services/location_service.dart';
import '../constants/admin_constants.dart';

class UmbrellaMapPage extends StatefulWidget {
  const UmbrellaMapPage({super.key});

  @override
  State<UmbrellaMapPage> createState() => _UmbrellaMapPageState();
}

class _UmbrellaMapPageState extends State<UmbrellaMapPage> {
  final DatabaseService _db = DatabaseService();
  final MapController _mapController = MapController();
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _checkAdminStatus();
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: "Machine Name",
                  hintText: "e.g. Station Alpha",
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                decoration: const InputDecoration(
                  labelText: "Landmark / Building",
                  hintText: "e.g. Science Block, Mall Annex",
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: slotCountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Number of Slots",
                  hintText: "e.g. 10",
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
                  slotCountController.text.isEmpty) {
                return;
              }

              final totalSlots = int.tryParse(slotCountController.text) ?? 0;
              // Generate fixed holder IDs: S1, S2, S3...
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

              // Capture context before async operation
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);

              try {
                if (existingMachine == null) {
                  await _db.addUmbrellaLocation(machine);
                } else {
                  await _db.updateUmbrellaLocation(machine);
                }

                if (!mounted) return;
                navigator.pop();
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      existingMachine == null
                          ? "Machine added"
                          : "Machine updated",
                    ),
                  ),
                );
              } catch (e) {
                if (!mounted) return;
                messenger.showSnackBar(SnackBar(content: Text("Error: $e")));
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
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(30),
            topRight: Radius.circular(30),
          ),
        ),
        padding: const EdgeInsets.all(24),
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
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        loc.description,
                        style: TextStyle(color: Colors.grey[600], fontSize: 16),
                      ),
                    ],
                  ),
                ),
                if (_isAdmin)
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Color(0xFF0066FF)),
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
            const Divider(height: 32),
            Text(
              "Management Overview",
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(15),
              ),
              child: Row(
                children: [
                  const Icon(Icons.grid_view_rounded, color: Color(0xFF0066FF)),
                  const SizedBox(width: 12),
                  Text(
                    "Total Slots: ${loc.totalSlots}",
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0066FF),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: loc.slotIds.length,
                itemBuilder: (context, index) => Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Text(
                    loc.slotIds[index],
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ],
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
          "Are you sure you want to delete '${location.machineName}'? This action is permanent.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              // Capture context before async operation
              final navigator = Navigator.of(context);

              await _db.deleteUmbrellaLocation(location.id);
              if (!mounted) return;
              navigator.pop();
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
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // Header with Gradient
          Container(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 10,
              bottom: 20,
              left: 24,
              right: 24,
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0066FF), Color(0xFF00CCFF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(30),
                bottomRight: Radius.circular(30),
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "RainNest Admin",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.logout_rounded,
                        color: Colors.white,
                      ),
                      onPressed: _logout,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Search Bar
                TypeAheadField<SearchResult>(
                  builder: (context, controller, focusNode) => TextField(
                    controller: controller,
                    focusNode: focusNode,
                    style: const TextStyle(color: Colors.black87),
                    decoration: InputDecoration(
                      hintText: "Search Building / College",
                      hintStyle: TextStyle(color: Colors.grey[400]),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: Color(0xFF0066FF),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  suggestionsCallback: (pattern) =>
                      LocationService.searchPlaces(pattern),
                  itemBuilder: (context, suggestion) => ListTile(
                    dense: true,
                    title: Text(
                      suggestion.name,
                      style: const TextStyle(fontSize: 13),
                    ),
                    leading: const Icon(
                      Icons.location_on_rounded,
                      color: Color(0xFF0066FF),
                      size: 18,
                    ),
                  ),
                  onSelected: (suggestion) {
                    _mapController.move(suggestion.location, 16.0);
                  },
                ),
              ],
            ),
          ),

          // Map Container
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: StreamBuilder<List<UmbrellaLocation>>(
                    stream: _db.getUmbrellaLocations(),
                    builder: (context, snapshot) {
                      final locations = snapshot.data ?? [];
                      final markers = locations.map((loc) {
                        return Marker(
                          point: LatLng(loc.latitude, loc.longitude),
                          width: 60,
                          height: 60,
                          child: GestureDetector(
                            onTap: () => _showLocationDetails(loc),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.2),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.all(8),
                              child: const Icon(
                                Icons.umbrella_rounded,
                                color: Color(0xFF0066FF),
                                size: 30,
                              ),
                            ),
                          ),
                        );
                      }).toList();

                      return FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: const LatLng(0, 0),
                          initialZoom: 2.0,
                          onTap: (tapPosition, point) =>
                              _manageMachine(point: point),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.example.rainnest',
                          ),
                          MarkerLayer(markers: markers),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),

          // Reserved Space for future functionalities (Unlabeled)
          const Expanded(flex: 2, child: SizedBox.shrink()),
        ],
      ),
    );
  }
}
