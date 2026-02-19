import 'package:flutter/material.dart';

class RainNestLoader extends StatefulWidget {
  final double size;
  final Color? color;

  const RainNestLoader({super.key, this.size = 50.0, this.color});

  @override
  State<RainNestLoader> createState() => _RainNestLoaderState();
}

class _RainNestLoaderState extends State<RainNestLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();

    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Outer Ring
            RotationTransition(
              turns: _controller,
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(
                    colors: [
                      Colors.transparent,
                      (widget.color ?? const Color(0xFF0066FF)).withValues(
                        alpha: 0.2,
                      ),
                      widget.color ?? const Color(0xFF0066FF),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
            // Inner Circle (White/Background)
            Container(
              width: widget.size * 0.8,
              height: widget.size * 0.8,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
            // Rain Drop / Umbrella Icon pulsing
            ScaleTransition(
              scale: Tween<double>(begin: 0.8, end: 1.2).animate(_animation),
              child: Icon(
                Icons.umbrella_rounded,
                color: widget.color ?? const Color(0xFF0066FF),
                size: widget.size * 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
