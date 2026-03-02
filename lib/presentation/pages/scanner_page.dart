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
import '../../data/models/transaction.dart';
import '../../services/database_service.dart';
import 'home_page.dart';

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

    setState(() {
      _isProcessing = true;
      _statusMessage = "Processing Return...";
    });

    try {
      final userProvider = context.read<UserProvider>();
      final userId = userProvider.user?.uid ?? "";

      await DatabaseService().returnUmbrella(
        transactionId: widget.returnRental!.transactionId,
        userId: userId,
        stationId: matchedStation.stationId,
        umbrellaId: widget.returnRental!.umbrellaId ?? '',
      );

      if (mounted) {
        setState(() {
          _isSuccess = true;
          _statusMessage = "Returned Successfully!";
        });

        Vibration.vibrate(duration: 200);
        await Future.delayed(const Duration(seconds: 1));

        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (context) => const HomePage(initialIndex: 1),
            ),
            (route) => false,
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

  void _proceedToPayment(Station targetStation) async {
    final userProvider = context.read<UserProvider>();
    final user = userProvider.user;
    if (user == null) return;

    if (targetStation.queueOrder.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No umbrellas available at this station")),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = "Calculating amount...";
    });

    try {
      final requiredPayment = await DatabaseService().getRequiredPayment(
        user.uid,
      );
      final umbrellaId = targetStation.queueOrder.first;

      if (user.walletBalance >= requiredPayment) {
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
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => PaymentProcessingPage(
          userId: userId,
          stationId: stationId,
          umbrellaId: umbrellaId,
          paymentId: paymentId,
          addedBalance: 0,
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
}
