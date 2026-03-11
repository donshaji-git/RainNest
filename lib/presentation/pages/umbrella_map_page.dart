import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../data/models/station.dart';
import '../../data/models/umbrella.dart';
import '../../data/models/user_model.dart';
import '../../services/database_service.dart';
import '../../services/auth_service.dart';
import '../../main.dart';
import '../../services/location_service.dart';
import '../constants/admin_constants.dart';
import '../../providers/location_provider.dart';
import '../../providers/map_provider.dart';
import 'dart:ui';
import '../widgets/rain_nest_loader.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';

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
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Analytics state
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;
  Map<int, Map<String, double>> _monthlyStats = {};
  bool _isLoadingStats = false;

  @override
  void initState() {
    super.initState();
    _checkAdminStatus();
    // Defer stats fetching to prioritize initial frame build and map rendering
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) _fetchStats();
    });

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

  void _fetchStats() async {
    if (mounted) setState(() => _isLoadingStats = true);
    try {
      final stats = await _db.getMonthlyRentalStats(
        _selectedMonth,
        _selectedYear,
      );
      if (mounted) {
        setState(() {
          _monthlyStats = stats;
          _isLoadingStats = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingStats = false);
      debugPrint("Error fetching stats: $e");
    }
  }

  void _logout() {
    // Trigger sign-out in background
    AuthService().signOut();
    // Navigate back to the AuthWrapper, which serves as our app's root router.
    // We must NEVER navigate directly to LoginPage because it drops the router tree.
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const AuthWrapper()),
        (route) => false,
      );
    }
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

    bool isSaving = false;
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
                  onPressed: isSaving
                      ? null
                      : () async {
                          final name = nameController.text.trim();
                          final qr = qrController.text.trim();
                          final desc = descController.text.trim();
                          final slotsText = slotCountController.text.trim();

                          if (name.isEmpty || slotsText.isEmpty || qr.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Please fill all fields"),
                              ),
                            );
                            return;
                          }

                          final totalSlots = int.tryParse(slotsText) ?? 0;
                          final queue = queueController.text
                              .split(",")
                              .map((e) => e.trim())
                              .where((e) => e.isNotEmpty)
                              .toList();

                          // Calculate total resistance for the station
                          double totalResistance = 0.0;
                          for (var uid in queue) {
                            totalResistance += double.tryParse(uid) ?? 0.0;
                          }

                          if (totalSlots < queue.length) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  "Slots ($totalSlots) cannot be less than umbrella count (${queue.length})",
                                ),
                              ),
                            );
                            return;
                          }

                          setDialogState(() => isSaving = true);

                          final navigator = Navigator.of(context);
                          try {
                            // Uniqueness check
                            final isUnique = await _db.isQrCodeUnique(
                              qr,
                              excludeStationId: existingStation?.stationId,
                            );
                            if (!isUnique) {
                              setDialogState(() => isSaving = false);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      "Machine QR ID already exists",
                                    ),
                                  ),
                                );
                              }
                              return;
                            }

                            final station = Station(
                              stationId: existingStation?.stationId ?? '',
                              name: name,
                              description: desc,
                              latitude:
                                  existingStation?.latitude ?? point!.latitude,
                              longitude:
                                  existingStation?.longitude ??
                                  point!.longitude,
                              totalSlots: totalSlots,
                              availableCount: queue.length,
                              freeSlotsCount: totalSlots - queue.length,
                              queueOrder: queue,
                              machineQrCode: qr,
                              totalResistance: totalResistance,
                            );

                            String finalStationId =
                                existingStation?.stationId ?? '';
                            if (existingStation == null) {
                              final stationRef = await _db.addStation(station);
                              if (stationRef != null) {
                                finalStationId = stationRef.id;
                              } else {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text("Failed to create station"),
                                    ),
                                  );
                                }
                                return; // Stop if we can't create the station
                              }
                            } else {
                              await _db.updateStation(station);
                            }

                            // Update/Create Umbrella table entries
                            for (var umbrellaId in queue) {
                              await _db.saveUmbrella(
                                Umbrella(
                                  umbrellaId: umbrellaId,
                                  resistance:
                                      double.tryParse(umbrellaId) ?? 0.0,
                                  stationId: finalStationId,
                                  status: 'available',
                                  createdAt: DateTime.now(),
                                ),
                              );
                            }

                            navigator.pop();
                          } catch (e) {
                            setDialogState(() => isSaving = false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text("Error: $e")),
                              );
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
                  child: isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(existingStation == null ? "Add" : "Save"),
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
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.bolt_rounded,
                      color: Colors.orange,
                      size: 30,
                    ),
                    const SizedBox(width: 15),
                    Text(
                      "Total Resistance: ${station.totalResistance.toStringAsFixed(1)} Ω",
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
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
      key: _scaffoldKey,
      backgroundColor: Colors.white,
      drawer: _buildAdminDrawer(),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Premium Admin Header
            _buildHeader(mapProvider),

            // Map Section
            Container(
              height: 400, // Fixed height for map to allow scrolling below
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

            // Analytics Section
            if (_isAdmin) _buildSalesAnalyticsSection(),

            const SizedBox(height: 20),

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
      ),
    );
  }

  Widget _buildSalesAnalyticsSection() {
    final totalRevenue = _monthlyStats.values.fold(
      0.0,
      (acc, val) => acc + (val['revenue'] ?? 0.0),
    );
    final totalFines = _monthlyStats.values.fold(
      0.0,
      (acc, val) => acc + (val['fines'] ?? 0.0),
    );
    final totalSecurity = _monthlyStats.values.fold(
      0.0,
      (acc, val) => acc + (val['security'] ?? 0.0),
    );
    final monthName = DateFormat(
      'MMMM',
    ).format(DateTime(_selectedYear, _selectedMonth));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Monthly Analytics",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      "$monthName $_selectedYear",
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  _buildMonthDropdown(),
                  const SizedBox(width: 4),
                  _buildYearDropdown(),
                ],
              ),
            ],
          ),
          const SizedBox(height: 30),
          Column(
            children: [
              _buildStatSummary(
                "Revenue",
                totalRevenue,
                const Color(0xFF0066FF),
                Icons.account_balance_wallet_rounded,
              ),
              const SizedBox(height: 12),
              _buildStatSummary(
                "Fines",
                totalFines,
                Colors.orange,
                Icons.gavel_rounded,
              ),
              const SizedBox(height: 12),
              _buildStatSummary(
                "Security",
                totalSecurity,
                Colors.green,
                Icons.security_rounded,
              ),
            ],
          ),
          const SizedBox(height: 30),
          SizedBox(
            height: 200,
            child: _isLoadingStats
                ? const Center(child: RainNestLoader())
                : _monthlyStats.isEmpty
                ? const Center(child: Text("No data for this month"))
                : _buildBarChart(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatSummary(
    String label,
    double total,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "₹${total.toStringAsFixed(0)}",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(color: Colors.grey[600], fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _selectedMonth,
          items: List.generate(12, (index) {
            final date = DateTime(2024, index + 1);
            return DropdownMenuItem(
              value: index + 1,
              child: Text(DateFormat('MMM').format(date)),
            );
          }),
          onChanged: (val) {
            if (val != null) {
              setState(() => _selectedMonth = val);
              _fetchStats();
            }
          },
        ),
      ),
    );
  }

  Widget _buildYearDropdown() {
    final currentYear = DateTime.now().year;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _selectedYear,
          items: List.generate(21, (index) {
            final year = (currentYear - 10) + index;
            return DropdownMenuItem(value: year, child: Text(year.toString()));
          }),
          onChanged: (val) {
            if (val != null) {
              setState(() => _selectedYear = val);
              _fetchStats();
            }
          },
        ),
      ),
    );
  }

  Widget _buildBarChart() {
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY:
            (_monthlyStats.values.isNotEmpty
                    ? _monthlyStats.values
                          .map(
                            (v) =>
                                (v['revenue'] ?? 0.0) +
                                (v['fines'] ?? 0.0) +
                                (v['security'] ?? 0.0),
                          )
                          .reduce((a, b) => a > b ? a : b)
                    : 0.0) *
                1.2 +
            10,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF1A1A1A),
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final stats = _monthlyStats[group.x];
              final rev = stats?['revenue'] ?? 0.0;
              final fine = stats?['fines'] ?? 0.0;
              final security = stats?['security'] ?? 0.0;
              return BarTooltipItem(
                'Day ${group.x}\n',
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                children: [
                  TextSpan(
                    text: 'Rev: ₹${rev.toStringAsFixed(0)}\n',
                    style: const TextStyle(
                      color: Colors.blueAccent,
                      fontSize: 12,
                    ),
                  ),
                  TextSpan(
                    text: 'Fine: ₹${fine.toStringAsFixed(0)}\n',
                    style: const TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 12,
                    ),
                  ),
                  TextSpan(
                    text: 'Sec: ₹${security.toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 12,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (value % 5 != 0 &&
                    value != 1 &&
                    value != _monthlyStats.length) {
                  return const SizedBox.shrink();
                }
                return Text(
                  value.toInt().toString(),
                  style: TextStyle(color: Colors.grey[400], fontSize: 10),
                );
              },
            ),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barGroups: _monthlyStats.entries.map((entry) {
          final rev = entry.value['revenue'] ?? 0.0;
          final fine = entry.value['fines'] ?? 0.0;
          final security = entry.value['security'] ?? 0.0;

          return BarChartGroupData(
            x: entry.key,
            barsSpace: 2, // Close together as requested
            barRods: [
              BarChartRodData(
                toY: rev,
                color: const Color(0xFF0066FF),
                width: 4,
                borderRadius: BorderRadius.circular(2),
              ),
              BarChartRodData(
                toY: fine,
                color: Colors.orange,
                width: 4,
                borderRadius: BorderRadius.circular(2),
              ),
              BarChartRodData(
                toY: security,
                color: Colors.green,
                width: 4,
                borderRadius: BorderRadius.circular(2),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildHeader(MapProvider mapProvider) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 10,
        bottom: 25,
        left: 20,
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
            children: [
              IconButton(
                icon: const Icon(
                  Icons.menu_rounded,
                  color: Colors.white,
                  size: 28,
                ),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Admin Center",
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      "Infrastructure Control",
                      style: GoogleFonts.outfit(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: _logout,
                child: Container(
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
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Search Bar integrated into header
          TypeAheadField<SearchResult>(
            builder: (context, controller, focusNode) => Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 15,
                  ),
                ],
              ),
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                decoration: InputDecoration(
                  hintText: "Search Building / College",
                  hintStyle: GoogleFonts.outfit(
                    color: Colors.grey,
                    fontSize: 14,
                  ),
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
                style: GoogleFonts.outfit(fontSize: 14),
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

  Widget _buildAdminDrawer() {
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.82,
      backgroundColor: const Color(0xFFF8FAFF),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: Column(
        children: [
          _buildDrawerHeader(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                const SizedBox(height: 20),
                _buildDrawerSectionTitle("OPERATIONS"),
                _buildDrawerItem(
                  icon: Icons.report_problem_rounded,
                  title: "Damage Reports",
                  onTap: () => _showReportsDialog(),
                ),
                _buildDrawerItem(
                  icon: Icons.inventory_2_rounded,
                  title: "Umbrella Inventory",
                  onTap: () => _showInventoryDialog(),
                ),
                _buildDrawerItem(
                  icon: Icons.account_balance_wallet_rounded,
                  title: "Wallet Blocker",
                  onTap: () => _showRedemptionBlockerDialog(),
                ),
                const SizedBox(height: 20),
                _buildDrawerSectionTitle("SYSTEM"),
                _buildDrawerItem(
                  icon: Icons.settings_rounded,
                  title: "Station Settings",
                  onTap: () => _showStationSettingsDialog(),
                ),
                _buildDrawerItem(
                  icon: Icons.analytics_outlined,
                  title: "Export Analytics",
                  onTap: () => _showExportSelector(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  "RainNest v1.0.2 Admin",
                  style: GoogleFonts.outfit(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerHeader() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 20,
        bottom: 30,
        left: 24,
        right: 24,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF0066FF),
        borderRadius: BorderRadius.only(bottomRight: Radius.circular(30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            radius: 30,
            backgroundColor: Colors.white24,
            child: Icon(
              Icons.admin_panel_settings_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            "System Admin",
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            FirebaseAuth.instance.currentUser?.email ?? "admin@rainnest.com",
            style: GoogleFonts.outfit(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 8, top: 12),
      child: Text(
        title,
        style: GoogleFonts.outfit(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.grey[400],
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF0066FF), size: 22),
      title: Text(
        title,
        style: GoogleFonts.outfit(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF1A1A1A),
        ),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
    );
  }

  void _showReportsDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        child: Container(
          padding: const EdgeInsets.all(24),
          width: MediaQuery.of(context).size.width * 0.95,
          height: MediaQuery.of(context).size.height * 0.8,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Damage Reports",
                    style: GoogleFonts.outfit(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: StreamBuilder<List<Station>>(
                  stream: _db.getStationsStream(),
                  builder: (context, stationSnapshot) {
                    final stations = stationSnapshot.data ?? [];
                    final Map<String, String> stationNames = {
                      for (var s in stations) s.stationId: s.name,
                    };

                    return StreamBuilder<List<Umbrella>>(
                      stream: _db.getUmbrellasStream(),
                      builder: (context, umbrellaSnapshot) {
                        final umbrellas = umbrellaSnapshot.data ?? [];
                        final Map<String, String> umbrellaToStation = {
                          for (var u in umbrellas)
                            u.umbrellaId: u.stationId ?? "",
                        };

                        return StreamBuilder<List<Map<String, dynamic>>>(
                          stream: _db.getDamageReportsStream(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            final reports = snapshot.data ?? [];
                            if (reports.isEmpty) {
                              return Center(
                                child: Text(
                                  "No records found",
                                  style: GoogleFonts.outfit(color: Colors.grey),
                                ),
                              );
                            }
                            return ListView.separated(
                              itemCount: reports.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(height: 24),
                              itemBuilder: (context, index) {
                                final r = reports[index];
                                final ts = (r['timestamp'] as Timestamp?)
                                    ?.toDate();
                                final uId = r['umbrellaId'] ?? "Unknown";
                                final sId = umbrellaToStation[uId];
                                final sName = stationNames[sId] ?? "In Transit";

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.report_gmailerrorred_rounded,
                                          size: 18,
                                          color: Colors.red,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: RichText(
                                            text: TextSpan(
                                              style: GoogleFonts.outfit(
                                                color: Colors.black,
                                                fontSize: 14,
                                              ),
                                              children: [
                                                TextSpan(
                                                  text: "Umbrella #$uId",
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                TextSpan(
                                                  text: " ($sName)",
                                                  style: TextStyle(
                                                    color: Colors.grey[600],
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        if (r['status'] == 'pending' ||
                                            r['status'] == 'pending_review' ||
                                            r['status'] == null)
                                          IconButton(
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            icon: const Icon(
                                              Icons
                                                  .check_circle_outline_rounded,
                                              color: Colors.green,
                                              size: 20,
                                            ),
                                            onPressed: () async {
                                              final messenger =
                                                  ScaffoldMessenger.of(context);
                                              await _db
                                                  .updateDamageReportStatus(
                                                    r['id'],
                                                    'solved',
                                                  );
                                              if (!mounted) return;
                                              messenger.showSnackBar(
                                                SnackBar(
                                                  content: const Text(
                                                    "Issue marked as solved",
                                                  ),
                                                  action: SnackBarAction(
                                                    label: "FIX",
                                                    onPressed: () => _db
                                                        .updateUmbrellaStatus(
                                                          uId,
                                                          'available',
                                                        ),
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        IconButton(
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          icon: const Icon(
                                            Icons.delete_outline_rounded,
                                            color: Colors.grey,
                                            size: 20,
                                          ),
                                          onPressed: () async => await _db
                                              .deleteDamageReport(r['id']),
                                        ),
                                        const SizedBox(width: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                (r['status'] == 'solved'
                                                        ? Colors.green
                                                        : Colors.red)
                                                    .withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: Text(
                                            (r['status'] ?? "NEW")
                                                .toString()
                                                .toUpperCase(),
                                            style: GoogleFonts.outfit(
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                              color: (r['status'] == 'solved'
                                                  ? Colors.green
                                                  : Colors.red),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      "Issue: ${r['type'] ?? 'N/A'}",
                                      style: GoogleFonts.outfit(
                                        fontSize: 14,
                                        color: Colors.grey[800],
                                      ),
                                    ),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                "Reported by: ${r['reporterName'] ?? r['userId']}",
                                                style: GoogleFonts.outfit(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              if (r['reporterPhone'] != null)
                                                InkWell(
                                                  onTap: () => _callPhoneNumber(
                                                    r['reporterPhone'],
                                                  ),
                                                  child: Text(
                                                    "📞 ${r['reporterPhone']}",
                                                    style: GoogleFonts.outfit(
                                                      fontSize: 12,
                                                      color: const Color(
                                                        0xFF0066FF,
                                                      ),
                                                      decoration: TextDecoration
                                                          .underline,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                (r['timing'] == 'before_rental'
                                                        ? Colors.purple
                                                        : Colors.blue)
                                                    .withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Text(
                                            r['timing'] == 'before_rental'
                                                ? "PRE-RENTAL"
                                                : "POST-USAGE",
                                            style: GoogleFonts.outfit(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color:
                                                  r['timing'] == 'before_rental'
                                                  ? Colors.purple
                                                  : Colors.blue,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    if (r['timing'] == 'before_rental' &&
                                        r['lastUserId'] != null &&
                                        r['status'] != 'deposit_blocked')
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton.icon(
                                          onPressed: () =>
                                              _showBlockDepositConfirmDialog(r),
                                          icon: const Icon(
                                            Icons.block_flipped,
                                            size: 16,
                                          ),
                                          label: const Text(
                                            "Block Previous User's Deposit",
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.red
                                                .withValues(alpha: 0.1),
                                            foregroundColor: Colors.red,
                                            elevation: 0,
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 8,
                                            ),
                                            textStyle: GoogleFonts.outfit(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    if (r['status'] == 'deposit_blocked')
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.red.withValues(
                                            alpha: 0.05,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: Colors.red.withValues(
                                              alpha: 0.2,
                                            ),
                                          ),
                                        ),
                                        child: Text(
                                          "✅ Deposit Blocked for User: ${r['blockedUserId']?.substring(0, 8)}...",
                                          style: GoogleFonts.outfit(
                                            fontSize: 11,
                                            color: Colors.red[700],
                                            fontWeight: FontWeight.w600,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    if (ts != null)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          top: 4.0,
                                        ),
                                        child: Text(
                                          "Date: ${DateFormat('MMM dd, hh:mm a').format(ts)}",
                                          style: GoogleFonts.outfit(
                                            fontSize: 10,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showInventoryDialog() {
    final searchController = TextEditingController();
    String searchQuery = "";

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(25),
            ),
            child: Container(
              padding: const EdgeInsets.all(24),
              width: MediaQuery.of(context).size.width * 0.95,
              height: MediaQuery.of(context).size.height * 0.8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Umbrella Inventory",
                        style: GoogleFonts.outfit(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context); // close inventory
                      _showAddUmbrellaDialog();
                    },
                    icon: const Icon(Icons.add_rounded),
                    label: const Text("Register New Umbrella"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0066FF),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 45),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: searchController,
                    onChanged: (val) {
                      setDialogState(() {
                        searchQuery = val.toLowerCase().trim();
                      });
                    },
                    decoration: InputDecoration(
                      hintText: "Search ID or Station...",
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: StreamBuilder<List<Station>>(
                      stream: _db.getStationsStream(),
                      builder: (context, stationSnapshot) {
                        final stations = stationSnapshot.data ?? [];
                        final Map<String, String> stationNames = {
                          for (var s in stations) s.stationId: s.name,
                        };

                        return StreamBuilder<List<Umbrella>>(
                          stream: _db.getUmbrellasStream(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            var umbrellas = snapshot.data ?? [];

                            // Apply Search Filter
                            if (searchQuery.isNotEmpty) {
                              umbrellas = umbrellas.where((u) {
                                final sName =
                                    stationNames[u.stationId]?.toLowerCase() ??
                                    "";
                                final uId = u.umbrellaId.toLowerCase();
                                return uId.contains(searchQuery) ||
                                    sName.contains(searchQuery);
                              }).toList();
                            }

                            if (umbrellas.isEmpty) {
                              return Center(
                                child: Text(
                                  "No umbrellas found",
                                  style: GoogleFonts.outfit(color: Colors.grey),
                                ),
                              );
                            }

                            return ListView.builder(
                              itemCount: umbrellas.length,
                              itemBuilder: (context, index) {
                                final u = umbrellas[index];
                                final isAvail = u.status == 'available';
                                final isDamaged = u.status == 'damaged';
                                final color = isAvail
                                    ? Colors.green
                                    : (isDamaged ? Colors.red : Colors.orange);

                                final sName =
                                    stationNames[u.stationId] ??
                                    (u.stationId != null
                                        ? "At Station"
                                        : "With User");

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(15),
                                    border: Border.all(
                                      color: color.withValues(alpha: 0.1),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.umbrella_rounded,
                                        color: color,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              "ID: ${u.umbrellaId}",
                                              style: GoogleFonts.outfit(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Row(
                                              children: [
                                                Icon(
                                                  u.stationId != null
                                                      ? Icons.location_on
                                                      : Icons.person,
                                                  size: 10,
                                                  color: Colors.grey[600],
                                                ),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    sName,
                                                    style: GoogleFonts.outfit(
                                                      fontSize: 10,
                                                      color: Colors.grey[600],
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            Text(
                                              "Res: ${u.resistance.toStringAsFixed(1)} Ω",
                                              style: GoogleFonts.outfit(
                                                fontSize: 10,
                                                color: Colors.grey[500],
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: color,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              u.status.toUpperCase(),
                                              style: GoogleFonts.outfit(
                                                fontSize: 8,
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          Transform.scale(
                                            scale: 0.65,
                                            child: Switch(
                                              value: u.status == 'maintenance',
                                              activeThumbColor: Colors.orange,
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              onChanged: u.status == 'rented'
                                                  ? null
                                                  : (val) async {
                                                      final messenger =
                                                          ScaffoldMessenger.of(
                                                            context,
                                                          );
                                                      await _db
                                                          .toggleUmbrellaMaintenance(
                                                            u.umbrellaId,
                                                            val,
                                                          );
                                                      if (!mounted) return;
                                                      messenger.showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                            val
                                                                ? "Locked for maintenance"
                                                                : "Available",
                                                          ),
                                                          backgroundColor: val
                                                              ? Colors.orange
                                                              : Colors.green,
                                                          duration:
                                                              const Duration(
                                                                seconds: 1,
                                                              ),
                                                        ),
                                                      );
                                                    },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showAddUmbrellaDialog() {
    final idController = TextEditingController();
    final resController = TextEditingController();
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text("Register Umbrella"),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: idController,
                  decoration: const InputDecoration(
                    labelText: "Umbrella ID",
                    hintText: "UMB-001",
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: resController,
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: "Resistance (Ohms)",
                    hintText: "1005.2",
                    helperText: "Read from NodeMCU Terminal",
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        final uId = idController.text.trim();
                        final resText = resController.text.trim();

                        if (uId.isEmpty || resText.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Fill all fields")),
                          );
                          return;
                        }

                        final resistance = double.tryParse(resText);
                        if (resistance == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Invalid resistance")),
                          );
                          return;
                        }

                        setDialogState(() => isSaving = true);
                        try {
                          await _db.saveUmbrella(
                            Umbrella(
                              umbrellaId: uId,
                              resistance: resistance,
                              status: 'available',
                              createdAt: DateTime.now(),
                            ),
                          );
                          if (context.mounted) {
                            Navigator.pop(context); // Close add dialog
                            _showInventoryDialog(); // Re-open inventory
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  "Umbrella Registered Successfully",
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          setDialogState(() => isSaving = false);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text("Error: $e")),
                            );
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0066FF),
                  foregroundColor: Colors.white,
                ),
                child: isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text("Save Umbrella"),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showStationSettingsDialog() {
    final searchController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(25),
            ),
            child: Container(
              padding: const EdgeInsets.all(24),
              width: MediaQuery.of(context).size.width * 0.9,
              height: MediaQuery.of(context).size.height * 0.8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Station Settings",
                        style: GoogleFonts.outfit(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: searchController,
                    onChanged: (val) => setDialogState(() {}),
                    decoration: InputDecoration(
                      hintText: "Search by name or ID...",
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: StreamBuilder<List<Station>>(
                      stream: _db.getStationsStream(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final query = searchController.text.toLowerCase();
                        final stations = (snapshot.data ?? []).where((s) {
                          return s.name.toLowerCase().contains(query) ||
                              s.stationId.toLowerCase().contains(query);
                        }).toList();

                        if (stations.isEmpty) {
                          return Center(
                            child: Text(
                              "No stations found",
                              style: GoogleFonts.outfit(color: Colors.grey),
                            ),
                          );
                        }

                        return ListView.builder(
                          itemCount: stations.length,
                          itemBuilder: (context, index) {
                            final s = stations[index];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(15),
                                border: Border.all(color: Colors.grey[200]!),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.03),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF0066FF,
                                      ).withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.location_on_rounded,
                                      color: Color(0xFF0066FF),
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          s.name,
                                          style: GoogleFonts.outfit(
                                            fontWeight: FontWeight.bold,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          "ID: ${s.stationId}",
                                          style: GoogleFonts.outfit(
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.edit_note_rounded,
                                      color: Color(0xFF0066FF),
                                    ),
                                    onPressed: () => _showStationEditDialog(s),
                                    tooltip: "Edit Station",
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showStationEditDialog(Station station) {
    final nameController = TextEditingController(text: station.name);
    final descController = TextEditingController(text: station.description);
    final latController = TextEditingController(
      text: station.latitude.toString(),
    );
    final lngController = TextEditingController(
      text: station.longitude.toString(),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Edit ${station.name}", style: GoogleFonts.outfit()),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: "Station Name",
                  labelStyle: GoogleFonts.outfit(),
                ),
              ),
              TextField(
                controller: descController,
                decoration: InputDecoration(
                  labelText: "Description",
                  labelStyle: GoogleFonts.outfit(),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: latController,
                      decoration: InputDecoration(
                        labelText: "Latitude",
                        labelStyle: GoogleFonts.outfit(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: lngController,
                      decoration: InputDecoration(
                        labelText: "Longitude",
                        labelStyle: GoogleFonts.outfit(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "CANCEL",
              style: GoogleFonts.outfit(color: Colors.grey),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final updated = Station(
                stationId: station.stationId,
                name: nameController.text,
                description: descController.text,
                totalSlots: station.totalSlots,
                availableCount: station.availableCount,
                freeSlotsCount: station.freeSlotsCount,
                queueOrder: station.queueOrder,
                machineQrCode: station.machineQrCode,
                latitude:
                    double.tryParse(latController.text) ?? station.latitude,
                longitude:
                    double.tryParse(lngController.text) ?? station.longitude,
              );
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              await _db.updateStation(updated);
              if (!mounted) return;
              navigator.pop();
              messenger.showSnackBar(
                const SnackBar(content: Text("Station updated successfully")),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0066FF),
              foregroundColor: Colors.white,
            ),
            child: Text("SAVE", style: GoogleFonts.outfit()),
          ),
        ],
      ),
    );
  }

  void _showExportSelector() {
    int selMonth = DateTime.now().month;
    int selYear = DateTime.now().year;
    bool isAllMonths = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setExportState) {
          return AlertDialog(
            title: Text("Export Analytics", style: GoogleFonts.outfit()),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CheckboxListTile(
                  title: Text(
                    "All Months (Full Year Report)",
                    style: GoogleFonts.outfit(fontSize: 14),
                  ),
                  value: isAllMonths,
                  onChanged: (val) => setExportState(() => isAllMonths = val!),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                if (!isAllMonths)
                  DropdownButtonFormField<int>(
                    initialValue: selMonth,
                    decoration: const InputDecoration(
                      labelText: "Select Month",
                    ),
                    items: List.generate(12, (i) {
                      return DropdownMenuItem(
                        value: i + 1,
                        child: Text(
                          DateFormat('MMMM').format(DateTime(2024, i + 1)),
                          style: GoogleFonts.outfit(),
                        ),
                      );
                    }),
                    onChanged: (val) => setExportState(() => selMonth = val!),
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: selYear,
                  decoration: const InputDecoration(labelText: "Select Year"),
                  items: List.generate(21, (i) {
                    final y = (DateTime.now().year - 10) + i;
                    return DropdownMenuItem(
                      value: y,
                      child: Text(y.toString(), style: GoogleFonts.outfit()),
                    );
                  }),
                  onChanged: (val) => setExportState(() => selYear = val!),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  "CANCEL",
                  style: GoogleFonts.outfit(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _exportAnalyticsReport(isAllMonths ? 0 : selMonth, selYear);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0066FF),
                  foregroundColor: Colors.white,
                ),
                child: Text("DOWNLOAD CSV", style: GoogleFonts.outfit()),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _exportAnalyticsReport(int month, int year) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      Map<int, Map<String, double>> stats = {};
      String fileName = "RainNest_Analytics_$year";

      if (month == 0) {
        // Full year - aggregate all months
        for (int m = 1; m <= 12; m++) {
          final mStats = await _db.getMonthlyRentalStats(m, year);
          if (mStats.isNotEmpty) {
            // Adjust day to be month-day for full year report
            mStats.forEach((day, data) {
              stats[(m * 100) + day] = data;
            });
          }
        }
        fileName += "_FullYear.csv";
      } else {
        stats = await _db.getMonthlyRentalStats(month, year);
        fileName += "_${DateFormat('MMM').format(DateTime(year, month))}.csv";
      }

      if (mounted) Navigator.pop(context); // Close loader

      if (stats.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("No data found for this period")),
          );
        }
        return;
      }

      // Create CSV
      List<List<dynamic>> rows = [];
      rows.add(["Date/Day", "Revenue (₹)", "Fines (₹)", "Security (₹)"]);

      var sortedKeys = stats.keys.toList()..sort();
      for (var key in sortedKeys) {
        String dateLabel;
        if (month == 0) {
          int m = key ~/ 100;
          int d = key % 100;
          dateLabel = "${DateFormat('MMM').format(DateTime(year, m))} $d";
        } else {
          dateLabel = "Day $key";
        }

        final data = stats[key]!;
        rows.add([
          dateLabel,
          data['revenue']?.toStringAsFixed(2) ?? "0.00",
          data['fines']?.toStringAsFixed(2) ?? "0.00",
          data['security']?.toStringAsFixed(2) ?? "0.00",
        ]);
      }

      // Create CSV manually for robustness
      String csvData = rows
          .map((row) {
            return row
                .map((cell) {
                  String str = cell.toString();
                  if (str.contains(',') ||
                      str.contains('\n') ||
                      str.contains('"')) {
                    return '"${str.replaceAll('"', '""')}"';
                  }
                  return str;
                })
                .join(',');
          })
          .join('\n');
      final directory = await getTemporaryDirectory();
      final path = "${directory.path}/$fileName";
      final file = File(path);
      await file.writeAsString(csvData);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path)],
          text: 'RainNest Admin Analytics Report',
        ),
      );
    } catch (e) {
      if (mounted) Navigator.pop(context);
      debugPrint("Export Error: $e");
    }
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

  void _callPhoneNumber(String? phone) async {
    if (phone == null) return;
    final Uri url = Uri.parse('tel:$phone');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      debugPrint("Could not launch $url");
    }
  }

  void _showBlockDepositConfirmDialog(Map<String, dynamic> report) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          "Block Security Deposit?",
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Damage was reported BEFORE a new rental. The previous user (UID: ${report['lastUserId']?.substring(0, 8) ?? 'Unknown'}...) may be responsible.",
              style: GoogleFonts.outfit(fontSize: 14),
            ),
            const SizedBox(height: 16),
            Text(
              "This will deduct ₹100 from their wallet/security deposit.",
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "CANCEL",
              style: GoogleFonts.outfit(color: Colors.grey),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              navigator.pop();
              try {
                await _db.blockSecurityDeposit(
                  userId: report['lastUserId'],
                  reportId: report['id'],
                  amount: 100.0,
                  reason:
                      "Damage reported pre-rental for umbrella #${report['umbrellaId']}",
                );
                if (!mounted) return;
                messenger.showSnackBar(
                  const SnackBar(content: Text("Deposit blocked successfully")),
                );
              } catch (e) {
                if (!mounted) return;
                messenger.showSnackBar(
                  SnackBar(
                    content: Text("Error: $e"),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text("BLOCK DEPOSIT", style: GoogleFonts.outfit()),
          ),
        ],
      ),
    );
  }

  void _showRedemptionBlockerDialog() {
    final searchController = TextEditingController();
    List<UserModel> foundUsers = [];
    bool isSearching = false;
    bool isInitialLoad = true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Initial load of blocked users
          if (isInitialLoad) {
            isInitialLoad = false;
            setDialogState(() => isSearching = true);
            _db.getBlockedUsers().then((users) {
              if (context.mounted) {
                setDialogState(() {
                  foundUsers = users;
                  isSearching = false;
                });
              }
            });
          }

          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(25),
            ),
            child: Container(
              padding: const EdgeInsets.all(24),
              width: MediaQuery.of(context).size.width * 0.9,
              height: MediaQuery.of(context).size.height * 0.75,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Wallet Blocker",
                        style: GoogleFonts.outfit(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: searchController,
                          decoration: InputDecoration(
                            hintText: "Enter Umbrella ID...",
                            prefixIcon: const Icon(Icons.umbrella_rounded),
                            filled: true,
                            fillColor: Colors.grey[100],
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: isSearching
                            ? null
                            : () async {
                                final query = searchController.text.trim();
                                if (query.isEmpty) return;
                                setDialogState(() => isSearching = true);
                                final users = await _db
                                    .getUsersAssociatedWithUmbrella(query);
                                setDialogState(() {
                                  foundUsers = users;
                                  isSearching = false;
                                });
                              },
                        icon: isSearching
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.search_rounded),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFF0066FF),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    foundUsers.isEmpty && !isSearching
                        ? "Currently no users blocked."
                        : (searchController.text.isNotEmpty
                              ? "Search results for #${searchController.text}:"
                              : "Currently Blocked Users:"),
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: foundUsers.isEmpty
                        ? Center(
                            child: Text(
                              isSearching ? "Loading..." : "No users found",
                              style: GoogleFonts.outfit(color: Colors.grey),
                            ),
                          )
                        : ListView.builder(
                            itemCount: foundUsers.length,
                            itemBuilder: (context, index) {
                              final user = foundUsers[index];
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(15),
                                  border: Border.all(color: Colors.grey[200]!),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.03,
                                      ),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: const Color(
                                            0xFF0066FF,
                                          ).withValues(alpha: 0.1),
                                          child: const Icon(
                                            Icons.person_rounded,
                                            color: Color(0xFF0066FF),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                user.name,
                                                style: GoogleFonts.outfit(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              Text(
                                                user.phoneNumber,
                                                style: GoogleFonts.outfit(
                                                  fontSize: 11,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                              Text(
                                                "Balance: ₹${user.walletBalance.toStringAsFixed(0)}",
                                                style: GoogleFonts.outfit(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: const Color(
                                                    0xFF0066FF,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Column(
                                          children: [
                                            Text(
                                              user.redemptionBlocked
                                                  ? "LOCKED"
                                                  : "OPEN",
                                              style: GoogleFonts.outfit(
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                color: user.redemptionBlocked
                                                    ? Colors.red
                                                    : Colors.green,
                                              ),
                                            ),
                                            Switch(
                                              value: user.redemptionBlocked,
                                              activeThumbColor: Colors.red,
                                              onChanged: (val) async {
                                                await _db
                                                    .toggleUserRedemptionBlock(
                                                      user.uid,
                                                      val,
                                                    );
                                                // Refresh list
                                                final updated =
                                                    searchController
                                                        .text
                                                        .isNotEmpty
                                                    ? await _db
                                                          .getUsersAssociatedWithUmbrella(
                                                            searchController
                                                                .text
                                                                .trim(),
                                                          )
                                                    : await _db
                                                          .getBlockedUsers();
                                                setDialogState(() {
                                                  foundUsers = updated;
                                                });
                                              },
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    if (user.redemptionBlocked &&
                                        user.walletBalance > 0)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: SizedBox(
                                          width: double.infinity,
                                          child: ElevatedButton.icon(
                                            onPressed: () => _showFineCollectionDialog(
                                              user,
                                              () async {
                                                // Refresh list after collection
                                                final updated =
                                                    searchController
                                                        .text
                                                        .isNotEmpty
                                                    ? await _db
                                                          .getUsersAssociatedWithUmbrella(
                                                            searchController
                                                                .text
                                                                .trim(),
                                                          )
                                                    : await _db
                                                          .getBlockedUsers();
                                                setDialogState(() {
                                                  foundUsers = updated;
                                                });
                                              },
                                            ),
                                            icon: const Icon(
                                              Icons.gavel_rounded,
                                              size: 14,
                                            ),
                                            label: Text(
                                              "Collect Fine (₹${user.walletBalance.toStringAsFixed(0)})",
                                              style: GoogleFonts.outfit(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.red
                                                  .withValues(alpha: 0.1),
                                              foregroundColor: Colors.red,
                                              elevation: 0,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showFineCollectionDialog(UserModel user, VoidCallback onCollected) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          "Collect Fine?",
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        content: Text(
          "This will deduct the entire balance of ₹${user.walletBalance.toStringAsFixed(0)} from ${user.name}'s wallet as a fine and UNBLOCK their account.",
          style: GoogleFonts.outfit(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "CANCEL",
              style: GoogleFonts.outfit(color: Colors.grey),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final messenger = ScaffoldMessenger.of(context);
              try {
                await _db.collectBlockedWalletAsFine(user.uid);
                onCollected();
                messenger.showSnackBar(
                  SnackBar(
                    content: Text("Fine collected from ${user.name}"),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text("Error: $e"),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text("COLLECT FINE", style: GoogleFonts.outfit()),
          ),
        ],
      ),
    );
  }
}
