import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/user_provider.dart';
import '../../services/database_service.dart';
import '../../data/models/user_model.dart';
import '../../data/models/transaction.dart';

class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final user = userProvider.user;

    if (user == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      body: SafeArea(
        child: StreamBuilder<UserModel?>(
          stream: DatabaseService().getUserStream(user.uid),
          builder: (context, userSnapshot) {
            final liveUser = userSnapshot.data ?? user;

            return Column(
              children: [
                _buildHeader(),
                const SizedBox(height: 20),
                _buildBalanceCard(context, liveUser),
                const SizedBox(height: 15),
                Expanded(
                  child: _buildTransactionHistory(context, liveUser.uid),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "My Wallet",
                style: GoogleFonts.outfit(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
              Text(
                "Manage your balance",
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0066FF).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.account_balance_wallet_rounded,
              color: Color(0xFF0066FF),
              size: 28,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceCard(BuildContext context, UserModel user) {
    final totalBalance = user.walletBalance - user.fineAccumulated;

    String redeemButtonText = "Redeem Balance";
    VoidCallback? onRedeemPressed;
    bool isPending = false;

    if (user.redemptionStatus == 'pending') {
      isPending = true;
      if (user.redemptionRequestedAt != null) {
        final now = DateTime.now();
        final diff = now.difference(user.redemptionRequestedAt!);
        final remainingDays = 5 - diff.inDays;
        redeemButtonText = remainingDays <= 0
            ? "Process Refund"
            : "Pending ($remainingDays days)";
        if (remainingDays <= 0) {
          onRedeemPressed = () => _handleProcessRedeem(user.uid);
        }
      }
    } else {
      onRedeemPressed = totalBalance > 0
          ? () => _handleRequestRedemption(user.uid)
          : null;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0066FF), Color(0xFF0044AA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0066FF).withValues(alpha: 0.3),
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
              Text(
                "Total Balance",
                style: GoogleFonts.outfit(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 16,
                ),
              ),
              Icon(
                Icons.account_balance_rounded,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            "₹${totalBalance.toStringAsFixed(2)}",
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 40,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (user.fineAccumulated > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "Includes ₹${user.fineAccumulated.toStringAsFixed(2)} fine due",
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 30),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onRedeemPressed,
                  icon: Icon(
                    isPending
                        ? Icons.hourglass_empty_rounded
                        : Icons.keyboard_return_rounded,
                  ),
                  label: Text(redeemButtonText),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF0066FF),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionHistory(BuildContext context, String uid) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(35),
          topRight: Radius.circular(35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(30, 30, 30, 20),
            child: Text(
              "Recent Transactions",
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1A1A1A),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<TransactionModel>>(
              stream: DatabaseService().getTransactionsStream(uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final transactions = snapshot.data ?? [];

                if (transactions.isEmpty) {
                  return Center(
                    child: Text(
                      "No transactions yet",
                      style: GoogleFonts.outfit(color: Colors.grey),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: transactions.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final tx = transactions[index];
                    // Credit = money coming IN or held on behalf of user
                    // deposit → user paid ₹100 held as security (debit from pocket)
                    // rental_fee → user paid ₹10 for rental (debit)
                    // penalty → extra charge (debit)
                    // refund → deposit returned to wallet (credit)
                    // topup → wallet top-up (credit)
                    final isCredit =
                        tx.type == 'refund' ||
                        tx.type == 'topup' ||
                        tx.type == 'return';
                    final isDebit =
                        tx.type == 'rental_fee' ||
                        tx.type == 'deposit' ||
                        tx.type == 'penalty' ||
                        tx.type == 'penalty_payment';

                    final title = _getTransactionTitle(tx.type);

                    // Pick the correct amount field
                    double amount = 0;
                    if (tx.type == 'deposit' || tx.type == 'refund') {
                      amount = tx.securityDeposit;
                    } else if (tx.type == 'penalty') {
                      amount = tx.penaltyAmount;
                    } else {
                      amount = tx.rentalAmount;
                    }

                    final dateStr = DateFormat(
                      'MMM dd, yyyy',
                    ).format(tx.timestamp);
                    final timeStr = DateFormat('hh:mm a').format(tx.timestamp);
                    final subtitle =
                        tx.umbrellaId != null && tx.umbrellaId!.isNotEmpty
                        ? "${tx.umbrellaId} • $dateStr $timeStr"
                        : "$dateStr • $timeStr";

                    final color = isCredit
                        ? Colors.green
                        : isDebit
                        ? Colors.red
                        : Colors.orange;
                    final sign = isCredit ? '+' : '-';

                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.grey.shade100),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(11),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isCredit
                                  ? Icons.arrow_downward_rounded
                                  : Icons.arrow_upward_rounded,
                              color: color,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: const Color(0xFF1A1A1A),
                                  ),
                                ),
                                Text(
                                  subtitle,
                                  style: GoogleFonts.outfit(
                                    color: Colors.grey[500],
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            "$sign₹${amount.toStringAsFixed(0)}",
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _getTransactionTitle(String type) {
    switch (type) {
      case 'rental_fee':
        return "Umbrella Rental";
      case 'return':
        return "Umbrella Returned";
      case 'deposit':
        return "Security Deposit";
      case 'refund':
        return "Deposit Refund";
      case 'topup':
        return "Wallet Top-up";
      case 'penalty':
        return "Late Return Fine";
      case 'penalty_payment':
        return "Fine Payment";
      default:
        return "Transaction";
    }
  }

  void _handleRequestRedemption(String uid) async {
    try {
      await DatabaseService().requestRedemption(uid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Refund request submitted! It will be verified within 5 days.",
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  void _handleProcessRedeem(String uid) async {
    try {
      await DatabaseService().redeemSecurityDeposit(uid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Security deposit refunded to wallet!")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }
}
