import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../services/database_service.dart';
import '../../data/models/transaction.dart';

class RentalHistoryPage extends StatelessWidget {
  final String userId;

  const RentalHistoryPage({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      appBar: AppBar(
        title: Text(
          "Rental History",
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1A1A1A),
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Color(0xFF1A1A1A),
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<List<TransactionModel>>(
        stream: DatabaseService().getTransactionsStream(userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                "Error loading history",
                style: GoogleFonts.outfit(color: Colors.red),
              ),
            );
          }

          // Filter for rental fees (initial rental)
          // We also want to find the corresponding 'return' transaction to show the return time
          final allTransactions = snapshot.data ?? [];
          final rentals = allTransactions
              .where((tx) => tx.type == 'rental_fee')
              .toList();

          if (rentals.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.history_rounded,
                    size: 64,
                    color: Colors.grey[300],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "No rental history found",
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      color: Colors.grey[400],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            itemCount: rentals.length,
            itemBuilder: (context, index) {
              final rentalTx = rentals[index];

              // Find the return transaction for this umbrella if it exists and happened AFTER the rental
              final returnTx = allTransactions
                  .cast<TransactionModel?>()
                  .firstWhere(
                    (tx) =>
                        tx?.type == 'return' &&
                        tx?.umbrellaId == rentalTx.umbrellaId &&
                        tx!.timestamp.isAfter(rentalTx.timestamp),
                    orElse: () => null,
                  );

              return _buildRentalCard(context, rentalTx, returnTx);
            },
          );
        },
      ),
    );
  }

  Widget _buildRentalCard(
    BuildContext context,
    TransactionModel rental,
    TransactionModel? returnTx,
  ) {
    final String umbrellaName = rental.umbrellaId ?? "Unknown Umbrella";

    final DateFormat formatter = DateFormat('MMM dd, yyyy • hh:mm a');
    final String rentalDate = formatter.format(rental.timestamp);
    final String returnDate = returnTx != null
        ? formatter.format(returnTx.timestamp)
        : (rental.status == 'active' || rental.status == 'late'
              ? "In Progress"
              : "Processing...");

    final Color statusColor = rental.status == 'late'
        ? Colors.red
        : (rental.status == 'active' ? Colors.blue : Colors.green);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: IntrinsicHeight(
          child: Row(
            children: [
              // Left status bar
              Container(width: 6, color: statusColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.umbrella_rounded,
                                color: statusColor,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                umbrellaName,
                                style: GoogleFonts.outfit(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF1A1A1A),
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              rental.status.toUpperCase(),
                              style: GoogleFonts.outfit(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: statusColor,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildInfoRow(
                        Icons.calendar_today_rounded,
                        "Rented",
                        rentalDate,
                      ),
                      const SizedBox(height: 12),
                      _buildInfoRow(
                        Icons.keyboard_return_rounded,
                        "Returned",
                        returnDate,
                        isReturn: true,
                        isActive:
                            rental.status == 'active' ||
                            rental.status == 'late',
                      ),
                      const Divider(
                        height: 32,
                        thickness: 1,
                        color: Color(0xFFF0F5FF),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Rental Fee",
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              color: Colors.grey[500],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            "₹${rental.rentalAmount.toStringAsFixed(2)}",
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF1A1A1A),
                            ),
                          ),
                        ],
                      ),
                      if (returnTx != null && returnTx.penaltyAmount > 0) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "Late Penalty",
                              style: GoogleFonts.outfit(
                                fontSize: 14,
                                color: Colors.red[400],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              "₹${returnTx.penaltyAmount.toStringAsFixed(2)}",
                              style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.red[400],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    IconData icon,
    String label,
    String value, {
    bool isReturn = false,
    bool isActive = false,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F5FF),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: const Color(0xFF0066FF)),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 11,
                color: Colors.grey[400],
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            Text(
              value,
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isActive && isReturn
                    ? const Color(0xFF0066FF)
                    : const Color(0xFF1A1A1A),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
