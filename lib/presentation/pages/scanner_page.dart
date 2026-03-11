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
  final bool isActive;
  const ScannerPage({super.key, this.returnRental, this.isActive = true});

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
  final bool _isSuccess = false;
  bool _hasScanned = false; // Prevents any second scan from being processed
  PaymentService? _paymentService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Give the UI a bit of time to settle before starting the camera
    if (widget.isActive) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && widget.isActive) {
          _controller.start();
        }
      });
    }
  }

  @override
  void didUpdateWidget(ScannerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      if (widget.isActive) {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted && widget.isActive) {
            _controller.start();
          }
        });
      } else {
        _controller.stop();
      }
    }
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
        if (widget.isActive) _controller.start();
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
    // ----- ONE-SHOT GUARD -----
    // Stop the scanner and block immediately on first valid trigger.
    if (_hasScanned || _isProcessing) return;
    _hasScanned = true;
    _controller.stop(); // camera off — no more frames
    Vibration.vibrate(duration: 100);
    // --------------------------

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
        setState(() {
          _isProcessing = true;
          _statusMessage = "Machine Found: ${matchedStation.name}";
        });

        // Short delay for visual feedback
        await Future.delayed(const Duration(milliseconds: 500));

        // Tell NodeMCU to blink orange (waiting for payment / selection)
        // We use a short timeout so the UI proceeds even if RTDB is slow
        try {
          await DatabaseService()
              .sendWaitingCommandToStation(matchedStation.stationId)
              .timeout(const Duration(seconds: 2));
        } catch (e) {
          debugPrint("Station sync timeout/error: $e");
        }

        if (mounted) {
          _proceedToPayment(matchedStation);
        }
        return;
      }

      // No match — show error popup
      if (mounted) {
        _showInvalidCodeDialog(code);
      }
      return;
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
        _isProcessing = false;
        _statusMessage = "Invalid Machine QR code";
      });
      _hasScanned = false;
      _controller.start();
      return;
    }

    final user = Provider.of<UserProvider>(context, listen: false).user;
    if (user == null) {
      setState(() {
        _isProcessing = false;
        _statusMessage = "User not logged in.";
      });
      _hasScanned = false;
      _controller.start();
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

      // Tell NodeMCU to blink orange (waiting for return confirmation)
      try {
        await DatabaseService()
            .sendWaitingCommandToStation(matchedStation.stationId)
            .timeout(const Duration(seconds: 2));
      } catch (e) {
        debugPrint("Station return sync timeout/error: $e");
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
        _hasScanned = false;
        _controller.start();
      }
    }
  }

  Future<bool?> _showPaymentWarning() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        bool agreedToTerms = false;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    color: Color(0xFF0066FF),
                  ),
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
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "By proceeding, you agree to the following:",
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildWarningItem(
                      Icons.account_balance_wallet_outlined,
                      "A ₹100 deposit is held for security purposes.",
                    ),
                    const SizedBox(height: 12),
                    _buildWarningItem(
                      Icons.money_off_csred_outlined,
                      "Late return fines will be deducted from your wallet balance.",
                    ),
                    const SizedBox(height: 12),
                    _buildWarningItem(
                      Icons.umbrella_outlined,
                      "You are responsible for returning the umbrella in good condition.",
                    ),
                    const SizedBox(height: 12),
                    _buildWarningItem(
                      Icons.timer_outlined,
                      "Withdrawal takes 2 days of verification.",
                    ),
                    const SizedBox(height: 20),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: CheckboxListTile(
                        value: agreedToTerms,
                        onChanged: (val) {
                          setState(() {
                            agreedToTerms = val ?? false;
                          });
                        },
                        title: Text(
                          "I agree to the terms and conditions",
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                        activeColor: const Color(0xFF0066FF),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
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
                  onPressed: agreedToTerms
                      ? () => Navigator.pop(context, true)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0066FF),
                    disabledBackgroundColor: Colors.grey[300],
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.grey[500],
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  child: Text(
                    "Proceed",
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        );
      },
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
      if (mounted) {
        setState(() => _statusMessage = "Processing refund cancellation...");
      }
      await DatabaseService().cancelRedemption(user.uid);
    }

    if (targetStation.queueOrder.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("No umbrellas available at this station"),
          ),
        );
        _hasScanned = false;
        _controller.start();
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isProcessing = true;
        _statusMessage = "Calculating amount...";
      });
    }

    try {
      // 1. Re-verify station availability from DB
      final latestStation = await DatabaseService().getStation(
        targetStation.stationId,
      );
      if (latestStation == null || latestStation.queueOrder.isEmpty) {
        if (mounted) {
          setState(() {
            _isProcessing = false;
            _statusMessage = "Sorry, no umbrellas left at this station.";
          });
          _hasScanned = false;
          _controller.start();
        }
        return;
      }

      // 2. Show withdrawal warning before calculating payment
      if (mounted) {
        final confirmed = await _showPaymentWarning();
        if (confirmed != true) {
          if (mounted) {
            setState(() {
              _isProcessing = false;
              _statusMessage = null;
            });
            _hasScanned = false;
            _controller.start();
          }
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
        _hasScanned = false;
        _controller.start();
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

  void _showInvalidCodeDialog(String code) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        // Auto-close after 3 seconds
        final navigator = Navigator.of(context);
        Future.delayed(const Duration(seconds: 3), () {
          if (navigator.canPop()) {
            navigator.pop();
          }
        });

        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.qr_code_scanner_rounded,
                    color: Colors.red,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  "Invalid QR Code",
                  style: GoogleFonts.outfit(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  "Scanned: \"$code\"",
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  "The scanned code is not a valid RainNest machine. Please make sure you are scanning the QR code on the station.",
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    color: Colors.grey[800],
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1A1A),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 12,
                    ),
                  ),
                  child: Text(
                    "Try Again",
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).then((_) {
      if (mounted) {
        _hasScanned = false;
        _controller.start();
        setState(() => _statusMessage = null);
      }
    });
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


}
