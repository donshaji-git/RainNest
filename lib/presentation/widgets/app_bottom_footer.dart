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

  const AppBottomFooter({
    super.key,
    required this.currentIndex,
    required this.onItemSelected,
  });

  @override
  Widget build(BuildContext context) {
    const double barHeight = 70.0;

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
              _buildNavItem(1, Icons.umbrella_rounded, "Umbrella"),
              const SizedBox(width: 48), // Gap for the central FAB
              _buildNavItem(3, Icons.account_balance_wallet_rounded, "Wallet"),
              _buildNavItem(4, Icons.person_rounded, "Profile"),
            ],
          ),
        ),
        // Central Floating Scan Button
        Positioned(
          top: -25,
          child: GestureDetector(
            onTap: () => onItemSelected(2),
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: const Color(0xFF0066FF),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0066FF).withValues(alpha: 0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
                border: Border.all(color: Colors.white, width: 4),
              ),
              child: const Icon(
                Icons.qr_code_scanner_rounded,
                color: Colors.white,
                size: 30,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
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
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
