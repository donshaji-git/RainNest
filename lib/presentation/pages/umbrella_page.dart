import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../../providers/user_provider.dart';
import '../../services/database_service.dart';
import '../../data/models/transaction.dart';
import '../../data/models/umbrella.dart';
import '../../data/models/station.dart';
import 'scanner_page.dart';

class UmbrellaPage extends StatefulWidget {
  final String? highlightUmbrellaId;
  const UmbrellaPage({super.key, this.highlightUmbrellaId});

  @override
  State<UmbrellaPage> createState() => _UmbrellaPageState();
}

class _UmbrellaPageState extends State<UmbrellaPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();

    // Sync fines on entrance
    Future.microtask(() {
      final user = context.read<UserProvider>().user;
      if (user != null) {
        DatabaseService().syncActiveFines(user.uid);
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final user = userProvider.user;

    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      body: SafeArea(
        child: StreamBuilder<List<TransactionModel>>(
          stream: DatabaseService().getActiveRentalsStream(user.uid),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final activeRentals = snapshot.data ?? [];

            return FadeTransition(
              opacity: _fadeAnim,
              child: CustomScrollView(
                slivers: [
                  _buildHeader(
                    activeRentals.length,
                    user.activeRentalIds.length,
                  ),
                  if (activeRentals.isEmpty)
                    SliverFillRemaining(child: _buildEmptyState())
                  else ...[
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
                      sliver: SliverToBoxAdapter(
                        child: Text(
                          "Active Rentals",
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) =>
                              _buildRentalCard(activeRentals[index], user.uid),
                          childCount: activeRentals.length,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(int count, int activeCount) {
    final atLimit = activeCount >= 3;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "My Umbrella",
                      style: GoogleFonts.outfit(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1A1A1A),
                      ),
                    ),
                    Text(
                      count == 0
                          ? "No active rentals"
                          : "$count / 3 umbrella${count > 1 ? 's' : ''} rented",
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0066FF).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.umbrella_rounded,
                    color: Color(0xFF0066FF),
                    size: 26,
                  ),
                ),
              ],
            ),
            if (atLimit) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.orange,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Maximum 3 umbrellas reached. Return one to rent more.",
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: Colors.orange[800],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xFF0066FF).withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.umbrella_rounded,
              size: 60,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            "No Umbrella Rented",
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Rent an umbrella from the home screen\nto see your active rentals here.",
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(color: Colors.grey, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildRentalCard(TransactionModel rental, String userId) {
    return FutureBuilder<Umbrella?>(
      future: DatabaseService().getUmbrella(rental.umbrellaId ?? ''),
      builder: (context, umbSnap) {
        final umbrella = umbSnap.data;
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F7FF),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.umbrella_rounded,
                        color: Color(0xFF0066FF),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Umbrella #${rental.umbrellaId ?? 'N/A'}",
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                              color: const Color(0xFF1A1A1A),
                            ),
                          ),
                          if (umbrella != null)
                            _StatusBadge(status: umbrella.status),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 14),

                // Details
                Row(
                  children: [
                    Expanded(
                      child: _DetailItem(
                        icon: Icons.access_time_rounded,
                        label: "Rented At",
                        value: DateFormat('hh:mm a').format(rental.timestamp),
                      ),
                    ),
                    Expanded(
                      child: _DetailItem(
                        icon: Icons.calendar_today_rounded,
                        label: "Date",
                        value: DateFormat('MMM dd').format(rental.timestamp),
                      ),
                    ),
                    Expanded(
                      child: _DetailItem(
                        icon: Icons.currency_rupee_rounded,
                        label: "Fee",
                        value: "₹${rental.rentalAmount.toStringAsFixed(0)}",
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),
                _CountdownBar(startTime: rental.timestamp),
                const SizedBox(height: 16),

                // Return button
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              ScannerPage(returnRental: rental),
                        ),
                      );
                    },
                    icon: const Icon(Icons.keyboard_return_rounded, size: 18),
                    label: Text(
                      "Return This Umbrella",
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0066FF),
                      side: const BorderSide(color: Color(0xFF0066FF)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    String label;
    switch (status) {
      case 'rented':
        bg = Colors.orange.withValues(alpha: 0.12);
        fg = Colors.orange[800]!;
        label = "In Use";
        break;
      case 'available':
        bg = Colors.green.withValues(alpha: 0.12);
        fg = Colors.green[800]!;
        label = "Available";
        break;
      default:
        bg = Colors.grey.withValues(alpha: 0.12);
        fg = Colors.grey[700]!;
        label = status;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        label,
        style: GoogleFonts.outfit(
          color: fg,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _DetailItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DetailItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF0066FF)),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: const Color(0xFF1A1A1A),
          ),
        ),
        Text(
          label,
          style: GoogleFonts.outfit(fontSize: 11, color: Colors.grey),
        ),
      ],
    );
  }
}

class _CountdownBar extends StatefulWidget {
  final DateTime startTime;
  const _CountdownBar({required this.startTime});

  @override
  State<_CountdownBar> createState() => _CountdownBarState();
}

class _CountdownBarState extends State<_CountdownBar> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final endTime = widget.startTime.add(const Duration(hours: 10));
    final remaining = endTime.difference(DateTime.now());
    final elapsed = DateTime.now().difference(widget.startTime);
    final total = const Duration(hours: 10);
    double progress = (elapsed.inSeconds / total.inSeconds).clamp(0.0, 1.0);

    final isOverdue = remaining.isNegative;
    final label = isOverdue ? "⚠ Time Up! Penalty Accruing" : _fmt(remaining);
    final color = isOverdue ? Colors.red : const Color(0xFF0066FF);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "Time Remaining",
              style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey[500]),
            ),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 7,
          ),
        ),
      ],
    );
  }

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return "${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}";
  }
}
