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

            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _buildHeader()),
                SliverToBoxAdapter(child: const SizedBox(height: 20)),
                SliverToBoxAdapter(child: _buildBalanceCard(context, liveUser)),
                SliverToBoxAdapter(child: const SizedBox(height: 12)),
                SliverToBoxAdapter(child: _buildCoinCard(context, liveUser)),
                SliverToBoxAdapter(child: const SizedBox(height: 15)),
                _buildTransactionHistory(context, liveUser.uid),
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
    final displayedBalance = user.totalBalance;

    String redeemButtonText = "Redeem Balance";
    VoidCallback? onRedeemPressed;
    bool isPending = false;

    if (user.redemptionStatus == 'pending') {
      isPending = true;
      if (user.redemptionRequestedAt != null) {
        final now = DateTime.now();
        final diff = now.difference(user.redemptionRequestedAt!);
        final remainingDays = 2 - diff.inDays;
        redeemButtonText = remainingDays <= 0
            ? "Process Refund"
            : "Pending ($remainingDays days)";
        if (remainingDays <= 0) {
          onRedeemPressed = () => _handleProcessRedeem(user.uid);
        }
      }
    } else {
      onRedeemPressed = displayedBalance > 0
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
                "Refundable Balance",
                style: GoogleFonts.outfit(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 16,
                ),
              ),
              const Icon(
                Icons.account_balance_wallet_rounded,
                color: Colors.white,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                "₹${displayedBalance.toStringAsFixed(0)}",
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              if (displayedBalance >= 100)
                Text(
                  "(Includes ₹100 Security)",
                  style: GoogleFonts.outfit(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 14,
                  ),
                ),
            ],
          ),

          if (user.hasSecurityDeposit)
            Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.verified_user_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      "Security Deposit: ₹100 (Held)",
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
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
                  "Outstanding Fine: ₹${user.fineAccumulated.toStringAsFixed(2)}",
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

  Widget _buildCoinCard(BuildContext context, UserModel user) {
    const int goal = 10000;
    final double progress = (user.coins / goal).clamp(0.0, 1.0);
    final bool canRedeem = user.coins >= goal;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.toll_rounded, color: Colors.amber, size: 22),
              const SizedBox(width: 8),
              Text(
                "${user.coins} Coins",
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
              const Spacer(),
              Text(
                canRedeem
                    ? "Ready to redeem!"
                    : "${goal - user.coins} more to go",
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: canRedeem ? Colors.green[700] : Colors.grey[500],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.grey[100],
              valueColor: AlwaysStoppedAnimation<Color>(
                canRedeem ? Colors.green : Colors.amber,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "100 coins = ₹1  •  10,000 coins = ₹10 reward",
            style: GoogleFonts.outfit(fontSize: 11, color: Colors.grey[400]),
          ),
          if (canRedeem) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        _handleRedeemCoins(context, user.uid, 'wallet'),
                    icon: const Icon(
                      Icons.account_balance_wallet_outlined,
                      size: 16,
                    ),
                    label: Text(
                      "Add ₹10 to Wallet",
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0066FF),
                      side: const BorderSide(color: Color(0xFF0066FF)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () =>
                        _handleRedeemCoins(context, user.uid, 'free_rental'),
                    icon: const Icon(Icons.umbrella_rounded, size: 16),
                    label: Text(
                      "Free Rental",
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0066FF),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTransactionHistory(BuildContext context, String uid) {
    return StreamBuilder<List<TransactionModel>>(
      stream: DatabaseService().getTransactionsStream(uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator()),
          );
        }

        // Filter out coin-related transactions and empty returns
        final transactions = (snapshot.data ?? []).where((tx) {
          if (tx.type.startsWith('coin_')) return false;
          if (tx.type == 'return' &&
              tx.rentalAmount == 0 &&
              (tx.coins ?? 0) == 0) {
            return false;
          }
          return true;
        }).toList();

        if (transactions.isEmpty) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                "No transactions yet",
                style: GoogleFonts.outfit(color: Colors.grey),
              ),
            ),
          );
        }

        return SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(35),
                    topRight: Radius.circular(35),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(30, 30, 30, 10),
                child: Text(
                  "Recent Transactions",
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1A1A1A),
                  ),
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final tx = transactions[index];
                  final isCredit = tx.type == 'refund' ||
                      tx.type == 'topup' ||
                      tx.type == 'return' ||
                      tx.type == 'coin_reward' ||
                      tx.type == 'coin_redeem_wallet';
                  final isDebit = tx.type == 'rental_fee' ||
                      tx.type == 'deposit' ||
                      tx.type == 'penalty' ||
                      tx.type == 'coin_redeem' ||
                      tx.type == 'penalty_payment';

                  final title = _getTransactionTitle(tx.type);

                  String amountText = "";
                  if (tx.type == 'coin_reward') {
                    amountText = "${tx.coins} Coins";
                  } else if (tx.type == 'deposit' || tx.type == 'refund') {
                    amountText = "₹${tx.securityDeposit.toStringAsFixed(0)}";
                  } else if (tx.type == 'penalty' ||
                      tx.type == 'penalty_payment') {
                    amountText = "₹${tx.penaltyAmount.toStringAsFixed(0)}";
                  } else {
                    amountText = "₹${tx.rentalAmount.toStringAsFixed(0)}";
                  }

                  final dateStr = DateFormat('MMM dd, yyyy').format(tx.timestamp);
                  final timeStr = DateFormat('hh:mm a').format(tx.timestamp);
                  final subtitle =
                      tx.umbrellaId != null && tx.umbrellaId!.isNotEmpty
                          ? "${tx.umbrellaId} • $dateStr $timeStr"
                          : "$dateStr • $timeStr";

                  final color = isCredit ? Colors.green : isDebit ? Colors.red : Colors.orange;
                  final sign = isCredit ? '+' : '-';
                  final icon = tx.type == 'coin_reward'
                      ? Icons.toll_rounded
                      : (isCredit
                          ? Icons.arrow_downward_rounded
                          : Icons.arrow_upward_rounded);

                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
                    decoration: const BoxDecoration(color: Colors.white),
                    child: Container(
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
                            child: Icon(icon, color: color, size: 18),
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
                            "$sign$amountText",
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                childCount: transactions.length,
              ),
            ),
            // Bottom padding for white background
            SliverToBoxAdapter(
              child: Container(height: 50, color: Colors.white),
            ),
          ],
        );
      },
    );
  }

  String _getTransactionTitle(String type) {
    switch (type) {
      case 'rental_fee':
        return "Rental";
      case 'return':
        return "Umbrella Returned";
      case 'deposit':
        return "Initial Deposit";
      case 'refund':
        return "Refund";
      case 'topup':
        return "Wallet Recharge";
      case 'penalty':
        return "Fine";
      case 'penalty_payment':
        return "Fine";
      case 'coin_reward':
        return "Coin Reward";
      case 'coin_redeem':
        return "Coins Redeemed";
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
              "Refund request submitted! It will be verified within 2 days.",
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
    final messenger = ScaffoldMessenger.of(context);
    try {
      await DatabaseService().redeemSecurityDeposit(uid);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text("Security deposit refunded to wallet!")),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _handleRedeemCoins(BuildContext context, String uid, String mode) async {
    final label = mode == 'wallet' ? "Add ₹10 to Wallet" : "Get Free Rental";
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          "Redeem 10,000 Coins",
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        content: Text(
          "This will burn 10,000 coins and ${mode == 'wallet' ? 'add ₹10 to your wallet' : 'grant you 1 free rental credit'}. Continue?",
          style: GoogleFonts.outfit(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              "Cancel",
              style: GoogleFonts.outfit(color: Colors.grey[600]),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0066FF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              label,
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);

    try {
      await DatabaseService().redeemCoins(uid, mode: mode);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            mode == 'wallet'
                ? "₹10 added to your wallet!"
                : "Free rental credit granted! Use it on your next booking.",
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }
}
