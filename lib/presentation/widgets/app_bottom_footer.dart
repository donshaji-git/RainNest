import 'package:flutter/material.dart';

/// A custom, production-ready bottom navigation footer for RainNest.
///
/// Features:
/// - Four navigation items: Home, Log, Wallet, Profile.
/// - A central floating circular action button (Scan) that overlaps the bar.
/// - Material 3 compatible and lightweight.
/// - Standalone and reusable.
class AppBottomFooter extends StatelessWidget {
  final int currentIndex;
  final Function(int) onItemSelected;
  final VoidCallback onScanPressed;

  const AppBottomFooter({
    super.key,
    required this.currentIndex,
    required this.onItemSelected,
    required this.onScanPressed,
  });

  @override
  Widget build(BuildContext context) {
    const double barHeight = 70.0;
    const double fabSize = 64.0;
    const double fabOverlap = 20.0; // How much the FAB overlaps the top

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        // Main Footer Bar
        Container(
          height: barHeight,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(30),
              topRight: Radius.circular(30),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, Icons.home_rounded, "Home"),
              _buildNavItem(1, Icons.assignment_rounded, "Log"),

              // Spacer for the center Scan button
              const SizedBox(width: fabSize),

              _buildNavItem(2, Icons.account_balance_wallet_rounded, "Wallet"),
              _buildNavItem(3, Icons.person_rounded, "Profile"),
            ],
          ),
        ),

        // Floating Scan Button
        Positioned(
          top: -fabOverlap,
          child: GestureDetector(
            onTap: onScanPressed,
            child: Container(
              width: fabSize,
              height: fabSize,
              decoration: BoxDecoration(
                color: const Color(0xFF0066FF),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0066FF).withValues(alpha: 0.4),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.qr_code_scanner_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    // Current Index 2 and 3 correspond to Wallet and Profile in the UI mapping
    // but the onItemSelected expects 0, 1, 2, 3.
    final isActive = currentIndex == index;
    final color = isActive ? const Color(0xFF0066FF) : Colors.grey[400];

    return Expanded(
      child: InkWell(
        onTap: () => onItemSelected(index),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
