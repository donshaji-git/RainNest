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
import 'login_page.dart';
import 'dart:ui';
import '../widgets/rain_nest_loader.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

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

  // Analytics state
  int _selectedMonth = DateTime.now().month;
  final int _selectedYear = DateTime.now().year;
  Map<int, Map<String, double>> _monthlyStats = {};
  bool _isLoadingStats = false;

  @override
  void initState() {
    super.initState();
    _checkAdminStatus();
    // Defer stats fetching and location initialization to prioritize initial frame build
    Future.delayed(const Duration(milliseconds: 300), () {
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
    setState(() => _isLoadingStats = true);
    try {
      final stats = await _db.getMonthlyRentalStats(
        _selectedMonth,
        _selectedYear,
      );
      setState(() {
        _monthlyStats = stats;
        _isLoadingStats = false;
      });
    } catch (e) {
      setState(() => _isLoadingStats = false);
      debugPrint("Error fetching stats: $e");
    }
  }

  void _logout() {
    // Trigger sign-out in background
    AuthService().signOut();
    // Navigate immediately for instantaneous feel
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginPage()),
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
                            );

                            String finalStationId =
                                existingStation?.stationId ?? '';
                            if (existingStation == null) {
                              final stationRef = await _db.addStation(station);
                              finalStationId = stationRef.id;
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
      (sum, val) => sum + (val['revenue'] ?? 0.0),
    );
    final totalFines = _monthlyStats.values.fold(
      0.0,
      (sum, val) => sum + (val['fines'] ?? 0.0),
    );
    final totalSecurity = _monthlyStats.values.fold(
      0.0,
      (sum, val) => sum + (val['security'] ?? 0.0),
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Monthly Analytics",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    "$monthName $_selectedYear",
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                ],
              ),
              _buildMonthDropdown(),
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
      padding: const EdgeInsets.symmetric(horizontal: 12),
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
