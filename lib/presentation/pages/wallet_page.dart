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
                _buildBalanceCard(context, liveUser.walletBalance),
                const SizedBox(height: 15),
                _buildSecurityDepositCard(liveUser),
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

  Widget _buildBalanceCard(BuildContext context, double balance) {
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
                Icons.contactless_rounded,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            "₹${balance.toStringAsFixed(2)}",
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 40,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 30),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Add Money Feature Coming Soon!"),
                      ),
                    );
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: const Text("Add Money"),
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

  Widget _buildSecurityDepositCard(UserModel user) {
    bool canRedeem = false;
    String statusMessage = "Deposit Not Paid";

    if (user.hasSecurityDeposit) {
      statusMessage = "Deposit Active";
      if (user.securityDepositDate != null) {
        final now = DateTime.now();
        final diff = now.difference(user.securityDepositDate!);
        if (diff.inDays >= 5) {
          canRedeem = true;
          statusMessage = "Redeemable";
        } else {
          statusMessage = "Redeemable in ${5 - diff.inDays} days";
        }
      }
    } else {
      return const SizedBox.shrink(); // Don't show if not paid
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7FF),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: const Color(0xFFCCE0FF)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Security Deposit",
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0066FF),
                  ),
                ),
                Text(
                  "₹100.00 • $statusMessage",
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: canRedeem ? () => _handleRedeem(user.uid) : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0066FF),
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey[200],
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: const Text("Redeem", style: TextStyle(fontSize: 12)),
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
                      const SizedBox(height: 15),
                  itemBuilder: (context, index) {
                    final tx = transactions[index];
                    final isCredit = tx.type == 'topup' || tx.type == 'refund';
                    final title = _getTransactionTitle(tx.type);
                    final dateStr = DateFormat(
                      'MMM dd, yyyy',
                    ).format(tx.timestamp);
                    final timeStr = DateFormat('hh:mm a').format(tx.timestamp);
                    final amount = tx.type == 'deposit' || tx.type == 'refund'
                        ? tx.securityDeposit
                        : tx.rentalAmount;

                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isCredit
                                  ? Colors.green.withValues(alpha: 0.1)
                                  : Colors.red.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isCredit
                                  ? Icons.arrow_downward_rounded
                                  : Icons.arrow_upward_rounded,
                              color: isCredit ? Colors.green : Colors.red,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: const Color(0xFF1A1A1A),
                                  ),
                                ),
                                Text(
                                  "$dateStr • $timeStr",
                                  style: GoogleFonts.outfit(
                                    color: Colors.grey[500],
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            "${isCredit ? '+' : '-'}₹${amount.toStringAsFixed(0)}",
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: isCredit ? Colors.green : Colors.red,
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
      case 'deposit':
        return "Security Deposit";
      case 'refund':
        return "Deposit Refund";
      case 'topup':
        return "Wallet Top-up";
      case 'penalty':
        return "Late Return Penalty";
      default:
        return "Transaction";
    }
  }

  void _handleRedeem(String uid) async {
    try {
      await DatabaseService().redeemSecurityDeposit(uid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Security deposit redeemed to wallet!")),
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
