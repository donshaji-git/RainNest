import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/database_service.dart';
import '../widgets/rain_nest_loader.dart';

class PaymentProcessingPage extends StatefulWidget {
  final String stationId;
  final String umbrellaId;
  final String paymentId;
  final double addedBalance;
  final String userId;

  const PaymentProcessingPage({
    super.key,
    required this.stationId,
    required this.umbrellaId,
    required this.paymentId,
    this.addedBalance = 0.0,
    required this.userId,
  });

  @override
  State<PaymentProcessingPage> createState() => _PaymentProcessingPageState();
}

class _PaymentProcessingPageState extends State<PaymentProcessingPage> {
  String _statusText = "Finalizing Rental...";
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    _finalizeProcess();
  }

  void _finalizeProcess() async {
    try {
      // 1. Brief delay for smooth UX transition
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;

      setState(() {
        _statusText = "Syncing with Station...";
      });

      // 2. Perform Database Finalization
      await DatabaseService().rentUmbrella(
        userId: widget.userId,
        stationId: widget.stationId,
        paymentId: widget.paymentId,
        addedBalance: widget.addedBalance,
      );

      if (!mounted) return;

      setState(() {
        _statusText = "Umbrella Unlocked!";
      });

      // 3. Final success delay
      await Future.delayed(const Duration(milliseconds: 1000));
      if (!mounted) return;

      // Navigate back to Home
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusText = "Error: $e";
          _isError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _isError
                ? const Icon(
                    Icons.error_outline_rounded,
                    color: Colors.red,
                    size: 80,
                  )
                : const RainNestLoader(size: 80, color: Color(0xFF0066FF)),
            const SizedBox(height: 40),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                _statusText,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: _isError ? Colors.red : const Color(0xFF1A1A1A),
                ),
              ),
            ),
            if (_isError) ...[
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Go Back"),
              ),
            ] else ...[
              const SizedBox(height: 10),
              Text(
                "Finalizing your rental session",
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  color: Colors.grey[500],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
