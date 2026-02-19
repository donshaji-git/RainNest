import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/rental_provider.dart';
import '../../providers/user_provider.dart';
import '../../data/models/station.dart';
import '../../services/payment_service.dart';
import 'payment_processing_page.dart';
import 'package:vibration/vibration.dart';
import '../../providers/station_provider.dart';
import '../../services/database_service.dart';

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

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

    final rentalProvider = context.read<RentalProvider>();

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

  void _proceedToPayment(Station targetStation) {
    final userProvider = context.read<UserProvider>();
    final user = userProvider.user;
    if (user == null) return;

    if (targetStation.queueOrder.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No umbrellas available at this station")),
      );
      return;
    }

    // Unified Payment Logic:
    // Required wallet balance is 100 Rs (security) + 10 Rs (rent) = 110 Rs
    // If user has less, calculate difference.
    final currentBalance = user.walletBalance;
    // If they already have 110+, they still pay 10 Rs rent from wallet?
    // Actually the logic is: always pay 10 Rs rent.
    // And ensure wallet has 100 Rs left.
    // So if currentBalance is 100, they need 10.
    // If currentBalance is 50, they need 60.

    double toPay = 0.0;
    if (currentBalance < 110.0) {
      toPay = 110.0 - currentBalance;
    } else {
      toPay =
          10.0; // They have enough, but we should decide if we deduct from wallet or pay again.
      // USER: "befor each rental make sure the that the wallet has 100 if not then calcutae the amount along with the rentall fee"
      // If balance is 150, 150 - 10 = 140 (OK).
    }

    final umbrellaId = targetStation.queueOrder.first;

    if (currentBalance >= 110.0) {
      // Direct rental from wallet balance
      _handleDirectRental(user.uid, targetStation.stationId, umbrellaId);
    } else {
      // Need to pay the difference via Razorpay
      _initiateRazorpayPayment(
        context: context,
        userId: user.uid,
        stationId: targetStation.stationId,
        umbrellaId: umbrellaId,
        amount: toPay,
        description: "Umbrella Rental & Deposit - RainNest",
        phone: user.phoneNumber,
        email: user.email,
        addedBalance: toPay - 10.0, // The portion that goes to security deposit
      );
    }
  }

  void _handleDirectRental(
    String userId,
    String stationId,
    String umbrellaId,
  ) async {
    setState(() {
      _isProcessing = true;
      _statusMessage = "Processing rental...";
    });

    try {
      final paymentId = 'wallet_${DateTime.now().millisecondsSinceEpoch}';
      await DatabaseService().rentUmbrella(
        userId: userId,
        stationId: stationId,
        paymentId: paymentId,
        addedBalance: 0,
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => PaymentProcessingPage(
            userId: userId,
            stationId: stationId,
            umbrellaId: umbrellaId,
            paymentId: paymentId,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _statusMessage = "Error: $e";
        });
      }
    }
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

        final paymentId =
            response.paymentId ??
            'pay_${DateTime.now().millisecondsSinceEpoch}';

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => PaymentProcessingPage(
              userId: userId,
              stationId: stationId,
              umbrellaId: umbrellaId,
              paymentId: paymentId,
              addedBalance: addedBalance,
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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            rentalProvider.isVerifying
                                ? "Verify Machine"
                                : "Scan QR Code",
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (rentalProvider.isVerifying)
                            Text(
                              "Scanning for: ${rentalProvider.targetStation?.name}",
                              style: GoogleFonts.outfit(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 16,
                              ),
                            ),
                        ],
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
                        rentalProvider.isVerifying
                            ? "Position the machine's QR code within the frame"
                            : "Position any RainNest QR code within the frame",
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
}
