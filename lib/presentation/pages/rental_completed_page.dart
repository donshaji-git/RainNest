import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'home_page.dart';

class RentalCompletedPage extends StatefulWidget {
  final double penalty;
  final int duration; // in minutes
  final DateTime timestamp;
  final String umbrellaId;
  final bool isDamaged;
  final String? damageType;

  const RentalCompletedPage({
    super.key,
    required this.penalty,
    required this.duration,
    required this.timestamp,
    required this.umbrellaId,
    this.isDamaged = false,
    this.damageType,
  });

  @override
  State<RentalCompletedPage> createState() => _RentalCompletedPageState();
}

class _RentalCompletedPageState extends State<RentalCompletedPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) return "$minutes mins";
    int hours = minutes ~/ 60;
    int remainingMins = minutes % 60;
    return "${hours}h ${remainingMins}m";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ScaleTransition(
                scale: _scaleAnimation,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: widget.isDamaged ? Colors.orange : Colors.green,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    widget.isDamaged ? Icons.report_problem : Icons.check,
                    color: Colors.white,
                    size: 60,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                widget.isDamaged
                    ? "Return & Damage Reported"
                    : "Successfully Returned",
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                "Thank you for using RainNest!",
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 48),
              _buildSummaryCard(),
              const Spacer(),
              _buildHomeButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FD),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey[100]!),
      ),
      child: Column(
        children: [
          _buildSummaryRow("Duration", _formatDuration(widget.duration)),
          const Divider(height: 24),
          _buildSummaryRow("Umbrella ID", widget.umbrellaId),
          const Divider(height: 24),
          _buildSummaryRow(
            "Final Fine",
            "₹${widget.penalty.toStringAsFixed(2)}",
            valueColor: widget.penalty > 0 ? Colors.red : Colors.green,
          ),
          if (widget.isDamaged) ...[
            const Divider(height: 24),
            _buildSummaryRow(
              "Condition",
              widget.damageType ?? "Damaged",
              valueColor: Colors.orange,
            ),
          ],
          const Divider(height: 24),
          _buildSummaryRow(
            "Return Time",
            DateFormat('hh:mm a, dd MMM').format(widget.timestamp),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.outfit(color: Colors.grey[600], fontSize: 14),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: valueColor ?? const Color(0xFF1A1A1A),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHomeButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: () {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const HomePage()),
            (route) => false,
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0066FF),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        child: Text(
          "Back to Home",
          style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
