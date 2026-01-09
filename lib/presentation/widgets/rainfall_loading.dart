import 'dart:math';
import 'package:flutter/material.dart';

class RainfallLoading extends StatefulWidget {
  const RainfallLoading({super.key});

  @override
  State<RainfallLoading> createState() => _RainfallLoadingState();
}

class _RainfallLoadingState extends State<RainfallLoading>
    with TickerProviderStateMixin {
  late AnimationController _mainController;
  late AnimationController _fadeController;

  final List<CloudData> _clouds = [];
  final List<RainDropData> _drops = [];
  final List<LeafData> _leaves = [];
  final Random _random = Random();

  late String _loadingText;
  final List<String> _loadingOptions = [
    "Connecting the clouds...",
    "Finding umbrellas nearby...",
    "Making rain a little nicer ☔",
    "Preparing your RainNest...",
    "Wait for the sun to peak...",
  ];

  @override
  void initState() {
    super.initState();
    _loadingText = _loadingOptions[_random.nextInt(_loadingOptions.length)];

    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..forward();

    // Initialize Clouds
    for (int i = 0; i < 6; i++) {
      _clouds.add(
        CloudData(
          x: _random.nextDouble(),
          y: 0.05 + _random.nextDouble() * 0.2,
          size: 150 + _random.nextDouble() * 100,
          speed: 0.02 + _random.nextDouble() * 0.03,
          opacity: 0.4 + _random.nextDouble() * 0.4,
        ),
      );
    }

    // Initialize Rain Drops (Collective motion)
    for (int i = 0; i < 80; i++) {
      _drops.add(
        RainDropData(
          x: _random.nextDouble(),
          y: _random.nextDouble(),
          speed: 0.2, // Uniform speed for collective motion
          length: 25 + _random.nextDouble() * 10,
          opacity: 0.3 + _random.nextDouble() * 0.4,
        ),
      );
    }

    // Initialize Leaves (Infrequent)
    for (int i = 0; i < 8; i++) {
      _leaves.add(
        LeafData(
          x: _random.nextDouble(),
          y: -0.2 - _random.nextDouble() * 1.0,
          speedY: 0.05 + _random.nextDouble() * 0.05,
          speedX: -0.02 + _random.nextDouble() * 0.04,
          rotationSpeed: 0.5 + _random.nextDouble() * 1.5,
          color: _random.nextBool()
              ? const Color(0xFFE67E22)
              : const Color(0xFFF1C40F),
          size: 8 + _random.nextDouble() * 8,
        ),
      );
    }
  }

  @override
  void dispose() {
    _mainController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // 1. SKY GRADIENT
          _buildSkyGradient(),

          // 2. MOVING CLOUDS
          _buildClouds(),

          // 3. FLAT LANDSCAPE (Meadow, Trees, Hills)
          _buildLandscape(),

          // 4. COORDINATED DIAGONAL RAIN
          _buildRain(),

          // 5. INFREQUENT FALLING LEAVES
          _buildLeaves(),

          // 6. CENTERED LOGO & TEXT
          _buildBranding(),
        ],
      ),
    );
  }

  Widget _buildSkyGradient() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF00ADEE), Color(0xFF0066FF)],
          // stops: [0.0, 1.0], // Simple two-color gradient as requested
        ),
      ),
    );
  }

  Widget _buildClouds() {
    return AnimatedBuilder(
      animation: _mainController,
      builder: (context, child) {
        return Stack(
          children: _clouds.map((cloud) {
            double currentX =
                (cloud.x + _mainController.value * cloud.speed * 8) % 1.5 - 0.4;
            return Positioned(
              left: MediaQuery.of(context).size.width * currentX,
              top: MediaQuery.of(context).size.height * cloud.y,
              child: CustomPaint(
                size: Size(cloud.size, cloud.size * 0.5),
                painter: CloudPainter(
                  opacity: cloud.opacity,
                ), // Opacity passed directly
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildLandscape() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        width: double.infinity,
        height: MediaQuery.of(context).size.height * 0.45,
        child: CustomPaint(painter: MeadowPainter()),
      ),
    );
  }

  Widget _buildRain() {
    return AnimatedBuilder(
      animation: _mainController,
      builder: (context, child) {
        return CustomPaint(
          size: Size.infinite,
          painter: CoordinatedRainPainter(
            drops: _drops,
            progress: _mainController.value,
          ),
        );
      },
    );
  }

  Widget _buildLeaves() {
    return AnimatedBuilder(
      animation: _mainController,
      builder: (context, child) {
        return CustomPaint(
          size: Size.infinite,
          painter: FallingLeavesPainter(
            leaves: _leaves,
            progress: _mainController.value,
          ),
        );
      },
    );
  }

  Widget _buildBranding() {
    return Center(
      child: FadeTransition(
        opacity: _fadeController,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/logo.png',
              height: 280,
              color: Colors.black,
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.beach_access,
                size: 150,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _loadingText.toUpperCase(),
              style: TextStyle(
                color: Colors.black.withOpacity(0.4),
                fontSize: 12,
                fontWeight: FontWeight.w400,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// DATA CLASSES
class CloudData {
  double x, y, size, speed, opacity;
  CloudData({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.opacity,
  });
}

class RainDropData {
  double x, y, speed, length, opacity;
  RainDropData({
    required this.x,
    required this.y,
    required this.speed,
    required this.length,
    required this.opacity,
  });
}

class LeafData {
  double x, y, speedY, speedX, rotationSpeed, size;
  Color color;
  LeafData({
    required this.x,
    required this.y,
    required this.speedY,
    required this.speedX,
    required this.rotationSpeed,
    required this.color,
    required this.size,
  });
}

// PAINTERS
class CloudPainter extends CustomPainter {
  final double opacity;
  CloudPainter({required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    // Instead of using MaskFilter.blur which can trigger Impeller issues when combined with certain opacities,
    // we use a simple fill with opacity. If blur is needed, it's safer to use it on a separate layer or optimize the path.
    final paint = Paint()
      ..color = Colors.white.withOpacity(opacity * 0.8)
      ..style = PaintingStyle.fill;
    // removed MaskFilter.blur to test if this is the cause of Impeller error

    final path = Path();
    path.addOval(
      Rect.fromLTWH(0, size.height * 0.3, size.width * 0.4, size.height * 0.6),
    );
    path.addOval(
      Rect.fromLTWH(size.width * 0.25, 0, size.width * 0.5, size.height),
    );
    path.addOval(
      Rect.fromLTWH(
        size.width * 0.6,
        size.height * 0.3,
        size.width * 0.4,
        size.height * 0.6,
      ),
    );

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CloudPainter oldDelegate) =>
      oldDelegate.opacity != opacity;
}

class MeadowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Distant Hills
    final hillPaint = Paint()..color = const Color(0xFF81C784).withOpacity(0.4);
    final hillPath = Path();
    hillPath.moveTo(0, size.height);
    hillPath.lineTo(0, size.height * 0.3);
    hillPath.quadraticBezierTo(
      size.width * 0.2,
      size.height * 0.1,
      size.width * 0.4,
      size.height * 0.25,
    );
    hillPath.quadraticBezierTo(
      size.width * 0.7,
      size.height * 0.4,
      size.width,
      size.height * 0.2,
    );
    hillPath.lineTo(size.width, size.height);
    hillPath.close();
    canvas.drawPath(hillPath, hillPaint);

    // Meadow Base
    final meadowPaint = Paint()..color = const Color(0xFF9CCC65);
    final meadowPath = Path();
    meadowPath.moveTo(0, size.height);
    meadowPath.lineTo(0, size.height * 0.6);
    meadowPath.quadraticBezierTo(
      size.width * 0.3,
      size.height * 0.45,
      size.width * 0.6,
      size.height * 0.65,
    );
    meadowPath.quadraticBezierTo(
      size.width * 0.85,
      size.height * 0.75,
      size.width,
      size.height * 0.55,
    );
    meadowPath.lineTo(size.width, size.height);
    meadowPath.close();
    canvas.drawPath(meadowPath, meadowPaint);

    _drawTrees(canvas, size);
  }

  void _drawTrees(Canvas canvas, Size size) {
    final treePaint = Paint()..color = const Color(0xFF2E7D32);
    final trunkPaint = Paint()..color = const Color(0xFF5D4037);

    void drawTree(double x, double y, double scale) {
      canvas.drawRect(
        Rect.fromLTWH(x - 2 * scale, y, 4 * scale, 10 * scale),
        trunkPaint,
      );
      final path = Path();
      path.moveTo(x, y - 30 * scale);
      path.lineTo(x - 15 * scale, y);
      path.lineTo(x + 15 * scale, y);
      path.close();
      canvas.drawPath(path, treePaint);
    }

    drawTree(size.width * 0.15, size.height * 0.6, 1.2);
    drawTree(size.width * 0.25, size.height * 0.65, 0.8);
    drawTree(size.width * 0.75, size.height * 0.68, 1.5);
    drawTree(size.width * 0.85, size.height * 0.62, 1.0);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class CoordinatedRainPainter extends CustomPainter {
  final List<RainDropData> drops;
  final double progress;
  CoordinatedRainPainter({required this.drops, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;

    for (var drop in drops) {
      // Collective motion: same speed, strictly vertical
      double currentY = (drop.y + progress * drop.speed * 10) % 1.0;
      double currentX = drop.x; // No horizontal drift

      paint.color = Colors.white.withOpacity(drop.opacity);

      double startX = currentX * size.width;
      double startY = currentY * size.height;
      double endX = startX; // Strictly vertical
      double endY = startY + drop.length;

      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CoordinatedRainPainter oldDelegate) => true;
}

class FallingLeavesPainter extends CustomPainter {
  final List<LeafData> leaves;
  final double progress;
  FallingLeavesPainter({required this.leaves, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (var leaf in leaves) {
      double currentY = (leaf.y + progress * leaf.speedY * 10) % 1.5 - 0.2;
      double currentX = (leaf.x + progress * leaf.speedX * 5) % 1.0;
      double currentRotation = (progress * leaf.rotationSpeed * 2 * pi);

      if (currentY < -0.1 || currentY > 1.1) continue;

      canvas.save();
      canvas.translate(currentX * size.width, currentY * size.height);
      canvas.rotate(currentRotation);

      paint.color = leaf.color.withOpacity(0.6);

      final path = Path();
      path.moveTo(0, -leaf.size);
      path.quadraticBezierTo(leaf.size * 0.6, 0, 0, leaf.size);
      path.quadraticBezierTo(-leaf.size * 0.6, 0, 0, -leaf.size);
      path.close();

      canvas.drawPath(path, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant FallingLeavesPainter oldDelegate) => true;
}
