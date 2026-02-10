import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:vibration/vibration.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:ui';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../services/database_service.dart';
import '../../data/models/user_model.dart';
import '../../data/models/umbrella.dart';
import '../../data/models/umbrella_rental.dart';
import '../../data/models/payment.dart';
import '../../providers/location_provider.dart';

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final MobileScannerController _controller = MobileScannerController();
  final DatabaseService _db = DatabaseService();
  bool _isScanFound = false;
  late Razorpay _razorpay;
  Umbrella? _pendingUmbrella;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) {
    if (_pendingUmbrella != null) {
      _finalizeRentalAfterPayment(_pendingUmbrella!);
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    setState(() => _isScanFound = false);
    _showErrorDialog("Payment Failed: ${response.message}");
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    _showErrorDialog(
      "External Wallet: ${response.walletName} not supported yet.",
    );
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_isScanFound) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty) {
      final String? code = barcodes.first.rawValue;
      if (code == null) return;

      setState(() => _isScanFound = true);

      // Non-blocking vibration
      Vibration.hasVibrator().then((hasVibrator) {
        if (hasVibrator ?? false) Vibration.vibrate(duration: 100);
      });

      if (!mounted) return;
      _processScannedUmbrella(code);
    }
  }

  void _processScannedUmbrella(String umbrellaId) async {
    _showLoadingDialog("Verifying Umbrella...");
    try {
      // 1. Verify Umbrella Exists and is available
      final umbrella = await _db.getUmbrella(umbrellaId);

      if (!mounted) return;
      Navigator.pop(context); // Dismiss loading

      if (umbrella == null) {
        _showErrorDialog("Invalid Umbrella QR Code");
        return;
      }

      if (umbrella.status != 'available') {
        _showErrorDialog("This umbrella is already rented or unavailable.");
        return;
      }

      // 2. Get Machine Details
      if (umbrella.currentMachineId == null) {
        _showErrorDialog("Umbrella is not assigned to any machine.");
        return;
      }

      _showSlotEntryDialog(umbrella);
    } catch (e) {
      debugPrint("Error processing umbrella: $e");
      _showErrorDialog(
        "Error occurred while processing scan. Please try again.",
      );
    }
  }

  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Text(message),
          ],
        ),
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Error"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _isScanFound = false);
            },
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  void _showSlotEntryDialog(Umbrella umbrella) async {
    final TextEditingController slotController = TextEditingController();

    UmbrellaRental? lastRental;
    try {
      lastRental = await _db.getLastCompletedRental(umbrella.id);
    } catch (e) {
      debugPrint("Warning: Could not fetch last rental (index missing?): $e");
      // Proceed without last return validation if query fails
    }

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Column(
          children: [
            const Text("Enter Slot Number"),
            const SizedBox(height: 8),
            Text(
              "Umbrella ID: ${umbrella.id}",
              style: GoogleFonts.outfit(
                fontSize: 14,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        content: TextField(
          controller: slotController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: "e.g. 1, 2, 3...",
            labelText: "Slot Number",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _isScanFound = false);
            },
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              if (slotController.text.isEmpty) return;
              final inputSlot = "S${slotController.text}";

              // Requirement: check whether the entered slot and umbrella id matches in the table of last return
              if (lastRental != null && lastRental.returnSlotId != inputSlot) {
                _showErrorDialog(
                  "Incorrect slot! According to records, this umbrella should be in ${lastRental.returnSlotId}. Found at $inputSlot.",
                );
                return;
              }

              // Fallback to umbrella currentSlotId if no referral record or as extra check
              if (umbrella.currentSlotId != null &&
                  umbrella.currentSlotId != inputSlot) {
                _showErrorDialog(
                  "Incorrect slot! Please enter the slot number from which you are taking the umbrella.",
                );
                return;
              }

              Navigator.pop(context);
              _showConfirmationDialog1(umbrella);
            },
            child: const Text("Continue"),
          ),
        ],
      ),
    );
  }

  void _showConfirmationDialog1(Umbrella umbrella) {
    bool isChecked = false;
    int secondsRemaining = 5;
    Timer? timer;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          timer ??= Timer.periodic(const Duration(seconds: 1), (t) {
            if (secondsRemaining > 0) {
              setDialogState(() => secondsRemaining--);
            } else {
              t.cancel();
            }
          });

          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text(
              "Confirmation",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "you should enter the correct slot of the umbrella which they scanned else any damage happened to the umbrellas has the full responsibility of the user",
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 15),
                const Text(
                  "unproper entry of the slot may lead to the responsibility of damage of other user",
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Checkbox(
                      value: isChecked,
                      onChanged: (val) =>
                          setDialogState(() => isChecked = val!),
                    ),
                    const Expanded(
                      child: Text("I understand and accept the responsibility"),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  timer?.cancel();
                  Navigator.pop(context);
                  setState(() => _isScanFound = false);
                },
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: (secondsRemaining == 0 && isChecked)
                    ? () {
                        timer?.cancel();
                        Navigator.pop(context);
                        _handlePaymentAndRental(umbrella);
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0066FF),
                  disabledBackgroundColor: Colors.grey[300],
                ),
                child: Text(
                  secondsRemaining > 0 ? "Wait ($secondsRemaining)" : "Confirm",
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _handlePaymentAndRental(Umbrella umbrella) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDoc = await _db.getUser(user.uid);
    if (userDoc == null) return;

    double rentalFee = 10.0;
    double currentWallet = userDoc.walletBalance;
    double totalToCharge = rentalFee;
    double walletTopUp = 0.0;

    if (currentWallet < 200) {
      walletTopUp = 200 - currentWallet;
      totalToCharge += walletTopUp;
    }

    if (totalToCharge > 0) {
      _pendingUmbrella = umbrella;
      _startRazorpayPayment(totalToCharge, userDoc);
    } else {
      _finalizeRentalAfterPayment(umbrella);
    }
  }

  void _startRazorpayPayment(double amount, UserModel user) {
    var options = {
      'key': dotenv.env['RAZORPAY_KEY'] ?? 'rzp_test_SEIpoU708OGD6p',
      'amount': (amount * 100).toInt(), // amount in paise
      'name': 'RainNest Umbrella Rental',
      'description': 'Payment for Umbrella Rental & Wallet Top-up',
      'prefill': {'contact': user.phoneNumber, 'email': user.email},
      'external': {
        'wallets': ['paytm'],
      },
    };

    try {
      _razorpay.open(options);
    } catch (e) {
      debugPrint('Error opening Razorpay: $e');
    }
  }

  void _finalizeRentalAfterPayment(Umbrella umbrella) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDoc = await _db.getUser(user.uid);
    if (userDoc == null) return;

    double rentalFee = 10.0;
    double currentWallet = userDoc.walletBalance;
    double walletTopUp = 0.0;

    if (currentWallet < 200) {
      walletTopUp = 200 - currentWallet;
    }

    try {
      final now = DateTime.now();

      // 1. Record Payments
      if (walletTopUp > 0) {
        await _db.recordPayment(
          Payment(
            id: '',
            userId: user.uid,
            amount: walletTopUp,
            type: 'FineRestoration',
            timestamp: now,
            status: 'success',
          ),
        );
      }
      await _db.recordPayment(
        Payment(
          id: '',
          userId: user.uid,
          amount: rentalFee,
          type: 'RentalFee',
          timestamp: now,
          status: 'success',
        ),
      );

      // 2. Update User Wallet and Rental Status
      await _db.updateUserWallet(user.uid, currentWallet + walletTopUp);

      // 3. Create Rental Record
      final machine = await _db.getUmbrellaLocation(umbrella.currentMachineId!);
      if (machine == null) throw "Machine not found";

      final locationProvider = Provider.of<LocationProvider>(
        context,
        listen: false,
      );
      final userLoc = locationProvider.currentLocation;

      final rental = UmbrellaRental(
        id: '',
        userId: user.uid,
        umbrellaId: umbrella.id,
        machineId: machine.id,
        machineName: machine.machineName,
        machineLat: machine.latitude,
        machineLon: machine.longitude,
        userLat: userLoc?.latitude ?? 9.9312,
        userLon: userLoc?.longitude ?? 76.2673,
        rentalTime: now,
        rentalFee: rentalFee,
        status: 'active',
      );
      String rentalId = await _db.createRental(rental);

      await _db.updateUserRentalStatus(
        user.uid,
        isRented: true,
        activeRentalId: rentalId,
      );

      // 4. Update Umbrella Status
      await _db.saveUmbrella(
        Umbrella(
          id: umbrella.id,
          currentMachineId: null,
          currentSlotId: null,
          status: 'rented',
          lastUserId: user.uid,
          updatedAt: now,
        ),
      );

      // 5. Update Machine available counts
      await _db.updateUmbrellaCounts(machine.id, deltaUmbrellas: -1);

      if (!mounted) return;
      _showConfirmationDialog2();
    } catch (e) {
      _showErrorDialog("Transaction failed: $e");
    }
  }

  void _showConfirmationDialog2() {
    bool isChecked = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Umbrella Unlocked!"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "check the umbrella condition so that you wont lost the money for damage that others made",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Checkbox(
                    value: isChecked,
                    onChanged: (val) => setDialogState(() => isChecked = val!),
                  ),
                  const Expanded(child: Text("I have checked the condition")),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: !isChecked
                  ? null
                  : () {
                      // Return logic (simulated)
                      Navigator.pop(context);
                      _showReturnOptions();
                    },
              child: const Text("Return"),
            ),
            ElevatedButton(
              onPressed: !isChecked
                  ? null
                  : () {
                      Navigator.pop(context);
                      Navigator.pop(context, "success");
                    },
              child: const Text("Confirm Order"),
            ),
          ],
        ),
      ),
    );
  }

  void _showReturnOptions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Return Options"),
        content: const Text(
          "Would you like to purchase a new one or return the rent money?",
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _isScanFound = false);
            },
            child: const Text("Purchase New One"),
          ),
          TextButton(
            onPressed: () {
              // Refund logic would go here
              Navigator.pop(context);
              setState(() => _isScanFound = false);
            },
            child: const Text("Return Rent Money"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Scanner View
          MobileScanner(controller: _controller, onDetect: _onDetect),

          // 2. Custom Overlay
          _buildOverlay(),

          // 3. Top Controls
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildGlassButton(
                    onTap: () => Navigator.pop(context),
                    icon: Icons.close_rounded,
                  ),
                  Text(
                    "Scan QR Code",
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  _buildGlassButton(
                    onTap: () => _controller.toggleTorch(),
                    icon: Icons.flashlight_on_rounded,
                  ),
                ],
              ),
            ),
          ),

          // 4. Bottom Tip
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  "Align QR code within the frame",
                  style: GoogleFonts.outfit(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverlay() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final double height = constraints.maxHeight;
        final double scanArea = width * 0.7;

        return Stack(
          children: [
            // Darkened background with a hole
            ColorFiltered(
              colorFilter: ColorFilter.mode(
                Colors.black.withValues(alpha: 0.5),
                BlendMode.srcOut,
              ),
              child: Stack(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      backgroundBlendMode: BlendMode.dstOut,
                    ),
                  ),
                  Align(
                    alignment: Alignment.center,
                    child: Container(
                      width: scanArea,
                      height: scanArea,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Corner borders
            Align(
              alignment: Alignment.center,
              child: Container(
                width: scanArea,
                height: scanArea,
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF0066FF), width: 2),
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
            ),

            // Scanning line (animation could be added here)
            Center(
              child: Container(
                width: scanArea - 40,
                height: 2,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF0066FF).withValues(alpha: 0),
                      const Color(0xFF0066FF),
                      const Color(0xFF0066FF).withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGlassButton({
    required VoidCallback onTap,
    required IconData icon,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            height: 45,
            width: 45,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _razorpay.clear();
    super.dispose();
  }
}
