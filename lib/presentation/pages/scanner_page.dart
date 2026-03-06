import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/rental_provider.dart';
import '../../providers/user_provider.dart';
import '../../data/models/station.dart';
import '../../services/payment_service.dart';
import 'payment_processing_page.dart';
import 'umbrella_return_verification_page.dart';
import 'package:vibration/vibration.dart';
import '../../providers/location_provider.dart';
import '../../providers/station_provider.dart';
import '../../data/models/transaction.dart';
import '../../services/database_service.dart';

class ScannerPage extends StatefulWidget {
  final TransactionModel? returnRental;
  const ScannerPage({super.key, this.returnRental});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> with WidgetsBindingObserver {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );
  bool _isProcessing = false;
  String? _statusMessage;
  bool _isSuccess = false;
  PaymentService? _paymentService;

  // Anti-double-scan logic
  String? _lastScannedCode;
  DateTime? _lastScanTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Give the UI a bit of time to settle before starting the camera
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _controller.start();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _paymentService?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_controller.value.isInitialized) return;

    switch (state) {
      case AppLifecycleState.resumed:
        _controller.start();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _controller.stop();
        break;
      case AppLifecycleState.hidden:
        break;
    }
  }

  void _onCodeScanned(String code) async {
    if (_isProcessing) return;

    // Haptic feedback
    Vibration.vibrate(duration: 100);

    // Global cooldown to prevent rapid fire
    final now = DateTime.now();
    if (_lastScanTime != null &&
        now.difference(_lastScanTime!).inMilliseconds < 1500) {
      if (code == _lastScannedCode) return;
    }
    _lastScanTime = now;
    _lastScannedCode = code;

    final rentalProvider = context.read<RentalProvider>();

    if (widget.returnRental != null) {
      _handleReturnScan(code);
      return;
    }

    if (!rentalProvider.isVerifying) {
      // General scan mode - try to find a matching station
      final stationProvider = context.read<StationProvider>();
      final matchedStation = stationProvider.stations.firstWhere(
        (s) => s.machineQrCode == code,
        orElse: () => Station(
          stationId: '',
          name: '',
          description: '',
          totalSlots: 0,
          availableCount: 0,
          freeSlotsCount: 0,
          queueOrder: [],
          machineQrCode: '',
          latitude: 0,
          longitude: 0,
        ),
      );

      if (matchedStation.stationId.isNotEmpty) {
        final userProvider = context.read<UserProvider>();
        if (widget.returnRental == null && userProvider.hasActiveRentals) {
          // General scan with active rentals: Ask user what they want to do
          _controller.stop();
          _showActionSelectionDialog(matchedStation);
          return;
        }

        rentalProvider.setTargetStation(matchedStation);
        setState(() {
          _statusMessage = "Machine Found: ${matchedStation.name}";
        });
        return;
      }

      setState(() {
        _statusMessage = "Scanned: $code\n(No matching machine found)";
      });

      // Auto-clear message after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _statusMessage != null && !_isProcessing) {
          setState(() => _statusMessage = null);
        }
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = "Verifying machine...";
    });

    final target = rentalProvider.targetStation!;
    if (code == target.machineQrCode) {
      setState(() {
        _isSuccess = true;
        _statusMessage = "Verified! Initiating payment...";
      });

      // Wait a moment for UX
      await Future.delayed(const Duration(seconds: 1));

      if (mounted) {
        _proceedToPayment(target);
      }
    } else {
      setState(() {
        _isProcessing = false;
        _isSuccess = false;
        _statusMessage = "Invalid Machine QR. Please scan the correct one.";
      });
    }
  }

  void _handleReturnScan(String code) async {
    final stationProvider = context.read<StationProvider>();
    final matchedStation = stationProvider.stations.firstWhere(
      (s) => s.machineQrCode == code,
      orElse: () => Station(
        stationId: '',
        name: '',
        description: '',
        totalSlots: 0,
        availableCount: 0,
        freeSlotsCount: 0,
        queueOrder: [],
        machineQrCode: '',
        latitude: 0,
        longitude: 0,
      ),
    );

    if (matchedStation.stationId.isEmpty) {
      setState(() {
        _statusMessage = "Invalid Machine QR code";
      });
      return;
    }

    final user = Provider.of<UserProvider>(context, listen: false).user;
    if (user == null) {
      setState(() {
        _statusMessage = "User not logged in.";
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = "Verifying machine and rental...";
    });

    try {
      // 1. Verify machine exists
      final station = await DatabaseService().getStation(
        matchedStation.stationId,
      );
      if (station == null) {
        throw Exception("Station not found");
      }

      // 2. Fetch active/late rental transaction
      final rentals = await DatabaseService().getUserTransactions(user.uid);

      // Use widget.returnRental if provided (ensure it's still valid/active)
      TransactionModel? activeRental;
      if (widget.returnRental != null) {
        activeRental = rentals.firstWhere(
          (t) =>
              t.transactionId == widget.returnRental!.transactionId &&
              (t.status == 'active' || t.status == 'late'),
          orElse: () => throw Exception("Selected rental is no longer active"),
        );
      } else {
        activeRental = rentals.firstWhere(
          (t) =>
              (t.status == 'active' || t.status == 'late') &&
              t.type == 'rental_fee',
          orElse: () => throw Exception("No active rental found"),
        );
      }

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => UmbrellaReturnVerificationPage(
              userId: user.uid,
              stationId: matchedStation.stationId,
              rental: activeRental!,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _statusMessage = "Error: $e";
        });
      }
    }
  }

  Future<bool?> _showPaymentWarning() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: Color(0xFF0066FF)),
            const SizedBox(width: 12),
            Text(
              "Notice Before Payment",
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "By proceeding with the payment, please note:",
              style: GoogleFonts.outfit(fontSize: 16, color: Colors.grey[800]),
            ),
            const SizedBox(height: 16),
            _buildWarningItem(
              Icons.timer_outlined,
              "Withdrawal takes 2 days of verification.",
            ),
            const SizedBox(height: 12),
            _buildWarningItem(
              Icons.account_balance_wallet_outlined,
              "Deposit is held for security purposes.",
            ),
            const SizedBox(height: 16),
            Text(
              "Do you wish to proceed to payment?",
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              "Cancel",
              style: GoogleFonts.outfit(
                color: Colors.grey[600],
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0066FF),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: Text(
              "Proceed to Payment",
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarningItem(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: const Color(0xFF0066FF)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.outfit(fontSize: 14, color: Colors.grey[700]),
          ),
        ),
      ],
    );
  }

  void _proceedToPayment(Station targetStation) async {
    final user = Provider.of<UserProvider>(context, listen: false).user;
    if (user == null) return;

    // Check for pending redemption
    final userData = await DatabaseService().getUser(user.uid);
    if (userData != null && userData.redemptionStatus == 'pending') {
      setState(() => _statusMessage = "Processing refund cancellation...");
      await DatabaseService().cancelRedemption(user.uid);
    }

    if (targetStation.queueOrder.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("No umbrellas available at this station"),
          ),
        );
      }
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = "Calculating amount...";
    });

    try {
      // 1. Re-verify station availability from DB
      final latestStation = await DatabaseService().getStation(
        targetStation.stationId,
      );
      if (latestStation == null || latestStation.queueOrder.isEmpty) {
        setState(() {
          _isProcessing = false;
          _statusMessage = "Sorry, no umbrellas left at this station.";
        });
        return;
      }

      // 2. Show withdrawal warning before calculating payment
      if (mounted) {
        final confirmed = await _showPaymentWarning();
        if (confirmed != true) {
          setState(() => _isProcessing = false);
          return;
        }
      }

      final requiredPayment = await DatabaseService().getRequiredPayment(
        user.uid,
      );
      final umbrellaId = latestStation.queueOrder.first;

      if (requiredPayment <= 0) {
        // Direct rental from wallet balance
        if (mounted) {
          _handleDirectRental(user.uid, targetStation.stationId, umbrellaId);
        }
      } else {
        // Need to pay via Razorpay
        if (mounted) {
          _initiateRazorpayPayment(
            context: context,
            userId: user.uid,
            stationId: targetStation.stationId,
            umbrellaId: umbrellaId,
            amount: requiredPayment,
            description: "Umbrella Rental & Deposit - RainNest",
            phone: user.phoneNumber,
            email: user.email,
            addedBalance: requiredPayment,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _statusMessage = "Error: $e";
        });
      }
    }
  }

  void _handleDirectRental(String userId, String stationId, String umbrellaId) {
    // Navigate to PaymentProcessingPage with addedBalance: 0
    // It will handle the rentUmbrella DB call using the wallet balance directly.
    final paymentId = 'wallet_${DateTime.now().millisecondsSinceEpoch}';
    final locationProvider = context.read<LocationProvider>();
    final loc = locationProvider.currentLocation;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => PaymentProcessingPage(
          userId: userId,
          stationId: stationId,
          umbrellaId: umbrellaId,
          paymentId: paymentId,
          addedBalance: 0,
          latitude: loc?.latitude,
          longitude: loc?.longitude,
        ),
      ),
    );
  }

  void _initiateRazorpayPayment({
    required BuildContext context,
    required String userId,
    required String stationId,
    required String umbrellaId,
    required double amount,
    required String description,
    required String phone,
    required String email,
    required double addedBalance,
  }) {
    _paymentService?.dispose();

    _paymentService = PaymentService(
      onSuccess: (response) async {
        if (!mounted) return;

        final locationProvider = context.read<LocationProvider>();
        final loc = locationProvider.currentLocation;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => PaymentProcessingPage(
              userId: userId,
              stationId: stationId,
              umbrellaId: umbrellaId,
              paymentId: response.paymentId ?? '',
              orderId: response.orderId,
              signature: response.signature,
              paymentLog: response.data != null
                  ? Map<String, dynamic>.from(response.data!)
                  : null,
              addedBalance: addedBalance,
              latitude: loc?.latitude,
              longitude: loc?.longitude,
            ),
          ),
        );
      },
      onFailure: (response) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Payment Failed: ${response.message}")),
          );
          setState(() {
            _isProcessing = false;
            _statusMessage = "Payment Failed. Try again.";
          });
        }
      },
    );

    _paymentService!.openCheckout(
      amount: amount,
      contact: phone,
      email: email,
      description: description,
    );
  }

  void _showManualEntryDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Enter Machine ID", style: GoogleFonts.outfit()),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: "e.g. M_001",
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.characters,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              final code = controller.text.trim();
              if (code.isNotEmpty) {
                Navigator.pop(context);
                _onCodeScanned(code);
              }
            },
            child: const Text("Verify"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rentalProvider = context.watch<RentalProvider>();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                if (barcode.rawValue != null) {
                  _onCodeScanned(barcode.rawValue!);
                }
              }
            },
            errorBuilder: (context, error, child) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error, color: Colors.red, size: 80),
                    const SizedBox(height: 16),
                    Text(
                      "Camera Error: ${error.errorCode}",
                      style: GoogleFonts.outfit(color: Colors.white),
                    ),
                    Text(
                      error.errorDetails?.message ?? "Unknown error",
                      style: GoogleFonts.outfit(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () => _controller.start(),
                      child: const Text("Retry"),
                    ),
                  ],
                ),
              );
            },
          ),
          // Gradient Overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.6),
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.8),
                ],
              ),
            ),
          ),
          // Overlay UI
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.returnRental != null
                                  ? "Scan Machine to Return"
                                  : (rentalProvider.isVerifying
                                        ? "Verify Machine"
                                        : "Scan QR Code"),
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (widget.returnRental != null)
                              Text(
                                "Umbrella #${widget.returnRental!.umbrellaId}",
                                style: GoogleFonts.outfit(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 16,
                                ),
                              )
                            else if (rentalProvider.isVerifying)
                              Text(
                                "Scanning for: ${rentalProvider.targetStation?.name}",
                                style: GoogleFonts.outfit(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 16,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      if (rentalProvider.isVerifying)
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => rentalProvider.clearVerification(),
                        ),
                    ],
                  ),
                ),
                const Spacer(),
                // Scanner Frame
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 260,
                      height: 260,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _isSuccess
                              ? Colors.green
                              : const Color(0xFF0066FF),
                          width: 4,
                        ),
                        borderRadius: BorderRadius.circular(40),
                      ),
                    ),
                    if (_isProcessing || _statusMessage != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _statusMessage!,
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 24,
                  ),
                  child: Column(
                    children: [
                      Text(
                        widget.returnRental != null
                            ? "Position the station's QR code to complete return"
                            : (rentalProvider.isVerifying
                                  ? "Position the machine's QR code within the frame"
                                  : "Position any RainNest QR code within the frame"),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextButton.icon(
                        onPressed: _showManualEntryDialog,
                        icon: const Icon(
                          Icons.keyboard_outlined,
                          color: Colors.white70,
                        ),
                        label: Text(
                          "Enter Code Manually",
                          style: GoogleFonts.outfit(
                            color: Colors.white70,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: 80), // Space for footer
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showActionSelectionDialog(Station station) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              "Station Found: ${station.name}",
              style: GoogleFonts.outfit(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "What would you like to do?",
              style: GoogleFonts.outfit(color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.umbrella_rounded,
                    label: "Rent",
                    color: const Color(0xFF0066FF),
                    onTap: () {
                      Navigator.pop(context);
                      context.read<RentalProvider>().setTargetStation(station);
                      _controller.start();
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.keyboard_return_rounded,
                    label: "Return",
                    color: Colors.orange,
                    onTap: () {
                      Navigator.pop(context);
                      _showRentalSelectionBottomSheet(station);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Center(
              child: TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _controller.start();
                },
                child: Text(
                  "Cancel",
                  style: GoogleFonts.outfit(color: Colors.grey),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRentalSelectionBottomSheet(Station station) async {
    final user = context.read<UserProvider>().user;
    if (user == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 20),
            Text(
              "Select Umbrella to Return",
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: StreamBuilder<List<TransactionModel>>(
                stream: DatabaseService().getActiveRentalsStream(user.uid),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final rentals = snapshot.data ?? [];
                  if (rentals.isEmpty) {
                    return const Center(child: Text("No active rentals found"));
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: rentals.length,
                    itemBuilder: (context, index) {
                      final rental = rentals[index];
                      return Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: const Icon(
                            Icons.umbrella_rounded,
                            color: Color(0xFF0066FF),
                          ),
                          title: Text("Umbrella #${rental.umbrellaId}"),
                          subtitle: Text(
                            "Rented on ${rental.timestamp.day}/${rental.timestamp.month}",
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (context) =>
                                    UmbrellaReturnVerificationPage(
                                      userId: user.uid,
                                      stationId: station.stationId,
                                      rental: rental,
                                    ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _controller.start();
              },
              child: const Text("Cancel"),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.outfit(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
