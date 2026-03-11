import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math' as math;
import 'rental_completed_page.dart';

/// Full-screen coin reward animation shown after a successful umbrella return.
/// Shows coins flying toward the wallet icon with a counter incrementing,
/// then auto-navigates to [RentalCompletedPage].
class CoinRewardAnimationPage extends StatefulWidget {
  final int coinsAwarded;
  final int previousCoinBalance;

  // RentalCompletedPage params
  final double penalty;
  final int duration;
  final DateTime timestamp;
  final String umbrellaId;
  final bool isDamaged;
  final String? damageType;

  const CoinRewardAnimationPage({
    super.key,
    required this.coinsAwarded,
    required this.previousCoinBalance,
    required this.penalty,
    required this.duration,
    required this.timestamp,
    required this.umbrellaId,
    this.isDamaged = false,
    this.damageType,
  });

  @override
  State<CoinRewardAnimationPage> createState() =>
      _CoinRewardAnimationPageState();
}

class _CoinRewardAnimationPageState extends State<CoinRewardAnimationPage>
    with TickerProviderStateMixin {
  // App background colour (matches the light theme used elsewhere)
  static const _bgLight = Color(0xFFF0F5FF);

  // Phase 1 — verification
  late AnimationController _verifyController;
  late Animation<double> _verifyOpacity;
  late Animation<double> _verifyScale;

  // Phase 2 — coins appear + info banner
  late AnimationController _coinsAppearController;
  late Animation<double> _coinsAppearScale;
  late Animation<double> _coinsAppearOpacity;

  // Phase 3 — coins fly to wallet
  late AnimationController _flyController;
  late Animation<double> _flyProgress;

  // Shimmer on counter
  late AnimationController _shimmerController;

  // Counter
  int _displayedCoins = 0;
  bool _showVerified = false;
  bool _showCoins = false;
  bool _showWallet = false;

  late List<_CoinParticle> _coins;

  @override
  void initState() {
    super.initState();

    final count = widget.coinsAwarded.clamp(6, 12); // show 6–12 coin visuals
    _coins = List.generate(count, (i) => _CoinParticle(i, count));
    _displayedCoins = widget.previousCoinBalance;

    // Verify phase
    _verifyController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _verifyOpacity = CurvedAnimation(
      parent: _verifyController,
      curve: Curves.easeOut,
    );
    _verifyScale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _verifyController, curve: Curves.elasticOut),
    );

    // Coins appear
    _coinsAppearController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _coinsAppearScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _coinsAppearController, curve: Curves.elasticOut),
    );
    _coinsAppearOpacity = CurvedAnimation(
      parent: _coinsAppearController,
      curve: Curves.easeIn,
    );

    // Fly
    _flyController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _flyProgress = CurvedAnimation(
      parent: _flyController,
      curve: Curves.easeInCubic,
    );

    // Shimmer
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _startSequence();
  }

  void _startSequence() async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() => _showVerified = true);
    await _verifyController.forward();

    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;

    setState(() => _showCoins = true);
    await _coinsAppearController.forward();

    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    setState(() => _showWallet = true);
    _flyController.forward();
    _animateCounter();

    await Future.delayed(const Duration(milliseconds: 1800));
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (ctx, anim, secAnim) => RentalCompletedPage(
          penalty: widget.penalty,
          duration: widget.duration,
          timestamp: widget.timestamp,
          umbrellaId: widget.umbrellaId,
          isDamaged: widget.isDamaged,
          damageType: widget.damageType,
        ),
        transitionsBuilder: (context2, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  void _animateCounter() async {
    final target = widget.previousCoinBalance + widget.coinsAwarded;
    final steps = widget.coinsAwarded.clamp(1, 30);
    final stepDelay = (1300 / steps).round();

    for (int i = 0; i < steps; i++) {
      await Future.delayed(Duration(milliseconds: stepDelay));
      if (!mounted) break;
      setState(() {
        _displayedCoins =
            widget.previousCoinBalance +
            ((widget.coinsAwarded * (i + 1)) / steps).round();
      });
    }
    if (mounted) setState(() => _displayedCoins = target);
  }

  @override
  void dispose() {
    _verifyController.dispose();
    _coinsAppearController.dispose();
    _flyController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    // Wallet sits at top-centre so coins arc toward it naturally
    final walletTarget = Offset(size.width * 0.5, size.height * 0.18);
    final coinOrigin = Offset(size.width * 0.5, size.height * 0.52);

    return Scaffold(
      backgroundColor: _bgLight,
      body: SafeArea(
        child: Stack(
          children: [
            // Soft radial background glow
            Positioned.fill(child: CustomPaint(painter: _GlowPainter())),

            // Floating particle sparkles
            const _SparkleField(),

            // ── MAIN CONTENT ──
            Column(
              children: [
                const SizedBox(height: 24),

                // ── Wallet target (top-centre) ──
                if (_showWallet)
                  _WalletTarget(flyProgress: _flyProgress)
                else
                  const SizedBox(height: 80),

                const SizedBox(height: 28),

                // ── Verification badge ──
                if (_showVerified)
                  FadeTransition(
                    opacity: _verifyOpacity,
                    child: ScaleTransition(
                      scale: _verifyScale,
                      child: _VerificationBadge(),
                    ),
                  ),

                const Spacer(),

                // ── Coin cluster (coin widgets arranged in arc) ──
                if (_showCoins) ...[
                  ScaleTransition(
                    scale: _coinsAppearScale,
                    child: FadeTransition(
                      opacity: _coinsAppearOpacity,
                      child: _StaticCoinCluster(count: _coins.length),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── Live counter ──
                  ScaleTransition(
                    scale: _coinsAppearScale,
                    child: FadeTransition(
                      opacity: _coinsAppearOpacity,
                      child: _CoinCounter(
                        coins: _displayedCoins,
                        shimmer: _shimmerController,
                      ),
                    ),
                  ),
                ],

                const Spacer(),

                // ── Info banner ──
                if (_showCoins)
                  FadeTransition(
                    opacity: _coinsAppearOpacity,
                    child: _InfoBanner(
                      coinsAwarded: widget.coinsAwarded,
                      totalCoins:
                          widget.previousCoinBalance + widget.coinsAwarded,
                    ),
                  ),
                const SizedBox(height: 32),
              ],
            ),

            // ── Flying coins (absolutely positioned) ──
            if (_showCoins)
              AnimatedBuilder(
                animation: _flyProgress,
                builder: (context, _) {
                  return Stack(
                    children: _coins.map((coin) {
                      final t =
                          (_flyProgress.value - coin.delay).clamp(0.0, 1.0) /
                          (1.0 - coin.delay).clamp(0.01, 1.0);

                      // Arc path: coins spread out first then converge to wallet
                      final midX = coinOrigin.dx + coin.offsetX * 80;
                      final midY = coinOrigin.dy - 60; // arc up

                      final x = _cubicBezierX(
                        coinOrigin.dx + coin.offsetX * 50,
                        midX,
                        walletTarget.dx,
                        t,
                      );
                      final y = _cubicBezierY(
                        coinOrigin.dy + coin.offsetY * 50,
                        midY,
                        walletTarget.dy,
                        t,
                      );

                      final opacity = _showWallet
                          ? (1.0 - t * t).clamp(0.0, 1.0)
                          : 1.0;
                      final scale = (1.0 - t * 0.5).clamp(0.1, 1.0);

                      return Positioned(
                        left: x - 30, // half of coin size 60
                        top: y - 30,
                        child: Opacity(
                          opacity: opacity,
                          child: Transform.scale(
                            scale: scale,
                            child: Transform.rotate(
                              angle:
                                  coin.rotation +
                                  _flyController.value *
                                      math.pi *
                                      2 *
                                      coin.spinSpeed,
                              child: const _CoinWidget(size: 60),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  double _cubicBezierX(double p0, double p1, double p2, double t) {
    return (1 - t) * (1 - t) * p0 + 2 * (1 - t) * t * p1 + t * t * p2;
  }

  double _cubicBezierY(double p0, double p1, double p2, double t) {
    return (1 - t) * (1 - t) * p0 + 2 * (1 - t) * t * p1 + t * t * p2;
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Coin particle data
// ──────────────────────────────────────────────────────────────────────────
class _CoinParticle {
  final double offsetX;
  final double offsetY;
  final double rotation;
  final double spinSpeed;
  final double delay;

  _CoinParticle(int index, int total)
    : offsetX = math.cos(index * math.pi * 2 / total),
      offsetY = math.sin(index * math.pi * 2 / total) * 0.6,
      rotation = index * 0.5,
      spinSpeed = 0.4 + index * 0.12,
      delay = (index / total) * 0.35;
}

// ──────────────────────────────────────────────────────────────────────────
// Individual coin visual
// ──────────────────────────────────────────────────────────────────────────
class _CoinWidget extends StatelessWidget {
  final double size;
  const _CoinWidget({this.size = 60});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-0.3, -0.3),
          colors: [
            Color(0xFFFFF9C4), // bright centre highlight
            Color(0xFFFFD600), // rich gold
            Color(0xFFFF8F00), // deep amber edge
          ],
          stops: [0.0, 0.55, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFD600).withValues(alpha: 0.7),
            blurRadius: 16,
            spreadRadius: 2,
          ),
          BoxShadow(
            color: const Color(0xFFFF8F00).withValues(alpha: 0.4),
            blurRadius: 6,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Center(
        child: Text(
          '₹',
          style: GoogleFonts.outfit(
            fontSize: size * 0.45,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF7B4F00),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Static coin cluster shown before they fly
// ──────────────────────────────────────────────────────────────────────────
class _StaticCoinCluster extends StatelessWidget {
  final int count;
  const _StaticCoinCluster({required this.count});

  @override
  Widget build(BuildContext context) {
    // Show up to 9 coins in a 3-row staggered grid-like arrangement
    final display = count.clamp(1, 9);
    final rows = [
      display >= 3 ? 3 : display,
      display >= 6 ? 3 : (display > 3 ? display - 3 : 0),
      display > 6 ? display - 6 : 0,
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int r = 0; r < rows.length; r++)
          if (rows[r] > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(rows[r], (c) {
                  final isOffset = r % 2 == 1;
                  return Padding(
                    padding: EdgeInsets.only(
                      left: c == 0 ? (isOffset ? 36 : 0) : 10,
                    ),
                    child: const _CoinWidget(size: 64),
                  );
                }),
              ),
            ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Verification badge
// ──────────────────────────────────────────────────────────────────────────
class _VerificationBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF00C853).withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFF00C853).withValues(alpha: 0.5),
              width: 2.5,
            ),
          ),
          child: const Icon(
            Icons.check_rounded,
            color: Color(0xFF00C853),
            size: 44,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Return Verified',
          style: GoogleFonts.outfit(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF1A1A1A),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Umbrella returned successfully',
          style: GoogleFonts.outfit(fontSize: 15, color: Colors.grey[500]),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Coin counter with shimmer
// ──────────────────────────────────────────────────────────────────────────
class _CoinCounter extends StatelessWidget {
  final int coins;
  final AnimationController shimmer;
  const _CoinCounter({required this.coins, required this.shimmer});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: shimmer,
      builder: (ctx, child) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0066FF).withValues(alpha: 0.12),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: const Color(
                  0xFFFFD600,
                ).withValues(alpha: 0.08 + shimmer.value * 0.12),
                blurRadius: 20,
                spreadRadius: 4,
              ),
            ],
            border: Border.all(
              color: const Color(
                0xFFFFD600,
              ).withValues(alpha: 0.3 + shimmer.value * 0.3),
              width: 2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _CoinWidget(size: 36),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$coins',
                    style: GoogleFonts.outfit(
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1A1A1A),
                      height: 1.0,
                    ),
                  ),
                  Text(
                    'Total Coins',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      color: Colors.grey[500],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Info banner: conversion rate + redemption milestone
// ──────────────────────────────────────────────────────────────────────────
class _InfoBanner extends StatelessWidget {
  final int coinsAwarded;
  final int totalCoins;
  const _InfoBanner({required this.coinsAwarded, required this.totalCoins});

  @override
  Widget build(BuildContext context) {
    final coinsToNext = (1000 - (totalCoins % 1000)) % 1000;
    final freeRentals = totalCoins ~/ 1000;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          // "+N coins earned" pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF0066FF),
              borderRadius: BorderRadius.circular(50),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0066FF).withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Text(
              '+$coinsAwarded coins earned 🎉',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Conversion card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                // Rate row
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const _CoinWidget(size: 28),
                    const SizedBox(width: 8),
                    Text(
                      '100 Coins  =  ₹1',
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1A1A1A),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(height: 1, color: Colors.grey[100]),
                const SizedBox(height: 8),

                // Rental row
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.umbrella_rounded,
                      color: const Color(0xFF0066FF),
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '1,000 Coins  =  1 Free Rental',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF0066FF),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Progress toward next free rental
                if (freeRentals > 0)
                  _progressChip(
                    '🎊  You have $freeRentals free rental${freeRentals > 1 ? 's' : ''} available!',
                    const Color(0xFF00C853),
                  )
                else if (coinsToNext > 0)
                  _progressChip(
                    '$coinsToNext more coins for a free rental',
                    const Color(0xFF0066FF),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _progressChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: GoogleFonts.outfit(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Wallet target (top-centre pulse)
// ──────────────────────────────────────────────────────────────────────────
class _WalletTarget extends StatelessWidget {
  final Animation<double> flyProgress;
  const _WalletTarget({required this.flyProgress});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: flyProgress,
      builder: (ctx, child) {
        final pulse = (math.sin(flyProgress.value * math.pi * 4)).abs() * 0.18;
        return Transform.scale(
          scale: 1.0 + pulse,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF0066FF), Color(0xFF00B2FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(
                    0xFF0066FF,
                  ).withValues(alpha: 0.35 + pulse),
                  blurRadius: 28,
                  spreadRadius: 4 + pulse * 18,
                ),
              ],
            ),
            child: const Icon(
              Icons.toll_rounded,
              color: Colors.white,
              size: 34,
            ),
          ),
        );
      },
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Decorative sparkle field (soft, matches light theme)
// ──────────────────────────────────────────────────────────────────────────
class _SparkleField extends StatelessWidget {
  const _SparkleField();

  @override
  Widget build(BuildContext context) {
    final rng = math.Random(17);
    final size = MediaQuery.of(context).size;
    return Stack(
      children: List.generate(30, (i) {
        final x = rng.nextDouble() * size.width;
        final y = rng.nextDouble() * size.height;
        final s = rng.nextDouble() * 5 + 2.0;
        final isGold = rng.nextBool();
        return Positioned(
          left: x,
          top: y,
          child: Container(
            width: s,
            height: s,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isGold
                  ? const Color(
                      0xFFFFD600,
                    ).withValues(alpha: rng.nextDouble() * 0.3 + 0.1)
                  : const Color(
                      0xFF0066FF,
                    ).withValues(alpha: rng.nextDouble() * 0.15 + 0.05),
            ),
          ),
        );
      }),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Background glow painter
// ──────────────────────────────────────────────────────────────────────────
class _GlowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    // Top blue radial
    paint.shader =
        RadialGradient(
          colors: [
            const Color(0xFF0066FF).withValues(alpha: 0.06),
            Colors.transparent,
          ],
        ).createShader(
          Rect.fromCircle(
            center: Offset(size.width / 2, size.height * 0.15),
            radius: size.width * 0.7,
          ),
        );
    canvas.drawCircle(
      Offset(size.width / 2, size.height * 0.15),
      size.width * 0.7,
      paint,
    );

    // Bottom gold radial
    paint.shader =
        RadialGradient(
          colors: [
            const Color(0xFFFFD600).withValues(alpha: 0.07),
            Colors.transparent,
          ],
        ).createShader(
          Rect.fromCircle(
            center: Offset(size.width / 2, size.height * 0.75),
            radius: size.width * 0.6,
          ),
        );
    canvas.drawCircle(
      Offset(size.width / 2, size.height * 0.75),
      size.width * 0.6,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
