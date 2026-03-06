import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'rental_completed_page.dart';
import '../../services/database_service.dart';
import '../../data/models/transaction.dart';
import '../../providers/rental_provider.dart';
import 'package:provider/provider.dart';

class ReturnInspectionStep {
  final String title;
  final String tooltip;
  final IconData icon;

  ReturnInspectionStep({
    required this.title,
    required this.tooltip,
    required this.icon,
  });
}

class UmbrellaReturnVerificationPage extends StatefulWidget {
  final String userId;
  final String stationId;
  final TransactionModel rental;

  const UmbrellaReturnVerificationPage({
    super.key,
    required this.userId,
    required this.stationId,
    required this.rental,
  });

  @override
  State<UmbrellaReturnVerificationPage> createState() =>
      _UmbrellaReturnVerificationPageState();
}

class _UmbrellaReturnVerificationPageState
    extends State<UmbrellaReturnVerificationPage> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  Timer? _timer;

  final List<ReturnInspectionStep> _steps = [
    ReturnInspectionStep(
      title: "Handle & Button",
      tooltip: "Check if the handle is firm and the open button clicks.",
      icon: Icons.pan_tool_alt_rounded,
    ),
    ReturnInspectionStep(
      title: "Canopy Cloth",
      tooltip: "Look for any tears, holes, or heavy staining.",
      icon: Icons.umbrella_rounded,
    ),
    ReturnInspectionStep(
      title: "Frame & Ribs",
      tooltip: "Ensure the metal frame isn't bent or broken.",
      icon: Icons.grid_view_rounded,
    ),
  ];

  bool _checkedHandle = false;
  bool _checkedCanopy = false;
  bool _checkedFrame = false;
  bool _isProcessing = false;
  int _remainingSeconds = 120; // 2 minutes timeout
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _startAutoPlay();
    _startCountdown();
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
        } else {
          timer.cancel();
          _autoReturn();
        }
      });
    });
  }

  void _autoReturn() {
    if (!_isProcessing) {
      // Set all checks to true for auto-return
      setState(() {
        _checkedHandle = true;
        _checkedCanopy = true;
        _checkedFrame = true;
      });
      _handleReturn();
    }
  }

  void _startAutoPlay() {
    _timer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (_currentStep < _steps.length - 1) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        );
      } else {
        _pageController.animateToPage(
          0,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _countdownTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  bool get _isAllChecked => _checkedHandle && _checkedCanopy && _checkedFrame;

  Future<void> _handleReturn() async {
    if (!_isAllChecked) return;
    setState(() => _isProcessing = true);

    try {
      final result = await DatabaseService().processFullReturn(
        transactionId: widget.rental.transactionId,
        userId: widget.userId,
        stationId: widget.stationId,
        umbrellaId: widget.rental.umbrellaId ?? '',
      );

      if (mounted) {
        context.read<RentalProvider>().clearVerification();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => RentalCompletedPage(
              penalty: result['penalty'] ?? 0.0,
              duration: result['duration'] ?? 0,
              timestamp: result['timestamp'] ?? DateTime.now(),
              umbrellaId: widget.rental.umbrellaId ?? '',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showReportDamageSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _DamageReportBottomSheet(
        onReport: (damageType) => _handleDamagedReturn(damageType),
      ),
    );
  }

  Future<void> _handleDamagedReturn(String damageType) async {
    setState(() => _isProcessing = true);
    Navigator.pop(context); // Close sheet

    try {
      final result = await DatabaseService().processFullReturn(
        transactionId: widget.rental.transactionId,
        userId: widget.userId,
        stationId: widget.stationId,
        umbrellaId: widget.rental.umbrellaId ?? '',
        isDamaged: true,
        damageType: damageType,
      );

      if (mounted) {
        context.read<RentalProvider>().clearVerification();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => RentalCompletedPage(
              penalty: result['penalty'] ?? 0.0,
              duration: result['duration'] ?? 0,
              timestamp: result['timestamp'] ?? DateTime.now(),
              umbrellaId: widget.rental.umbrellaId ?? '',
              isDamaged: true,
              damageType: damageType,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Column(
          children: [
            Text("Post-Usage Inspection", style: GoogleFonts.outfit()),
            Text(
              "Auto-confirm in ${_remainingSeconds ~/ 60}:${(_remainingSeconds % 60).toString().padLeft(2, '0')}",
              style: GoogleFonts.outfit(
                fontSize: 12,
                color: _remainingSeconds < 30 ? Colors.red : Colors.grey[600],
              ),
            ),
          ],
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildAnimatedSteps(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    _buildChecklistSection(),
                    const SizedBox(height: 16),
                    _buildDamageOption(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            _buildReturnButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedSteps() {
    return Column(
      children: [
        SizedBox(
          height: 280,
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (idx) => setState(() => _currentStep = idx),
            itemCount: _steps.length,
            itemBuilder: (context, index) {
              return _ReturnInspectionStepWidget(
                step: _steps[index],
                index: index,
              );
            },
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            _steps.length,
            (index) => AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: _currentStep == index ? 24 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: _currentStep == index
                    ? const Color(0xFF0052D1)
                    : Colors.grey[300],
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildChecklistSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FD),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey[100]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Confirm Condition",
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 16),
          _buildCheckItem(
            "Handle & Grip OK",
            _checkedHandle,
            (v) => setState(() => _checkedHandle = v!),
          ),
          _buildCheckItem(
            "Canopy Cloth OK",
            _checkedCanopy,
            (v) => setState(() => _checkedCanopy = v!),
          ),
          _buildCheckItem(
            "Frame OK",
            _checkedFrame,
            (v) => setState(() => _checkedFrame = v!),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckItem(
    String text,
    bool value,
    ValueChanged<bool?> onChanged,
  ) {
    return CheckboxListTile(
      value: value,
      onChanged: (v) {
        HapticFeedback.lightImpact();
        onChanged(v);
      },
      title: Text(text, style: GoogleFonts.outfit(fontSize: 16)),
      activeColor: const Color(0xFF0052D1),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    );
  }

  Widget _buildDamageOption() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: TextButton.icon(
        onPressed: _showReportDamageSheet,
        icon: const Icon(Icons.report_problem_outlined, color: Colors.red),
        label: Text(
          "Report Damage Instead",
          style: GoogleFonts.outfit(
            color: Colors.red,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildReturnButton() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: (_isAllChecked && !_isProcessing) ? _handleReturn : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0052D1),
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey[200],
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 0,
          ),
          child: _isProcessing
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3,
                  ),
                )
              : Text(
                  "Return Umbrella",
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ),
    );
  }
}

class _ReturnInspectionStepWidget extends StatelessWidget {
  final ReturnInspectionStep step;
  final int index;
  const _ReturnInspectionStepWidget({required this.step, required this.index});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (index == 0) _HandleGlowAnimation(),
                if (index == 1) _CanopyZoomAnimation(),
                if (index == 2) _FrameHighlightAnimation(),
                Icon(
                  step.icon,
                  size: 80,
                  color: const Color(0xFF0052D1).withValues(alpha: 0.8),
                ),
                if (index == 1) _ScanningLightOverlay(),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            step.title,
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            step.tooltip,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(fontSize: 14, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

class _HandleGlowAnimation extends StatefulWidget {
  @override
  State<_HandleGlowAnimation> createState() => _HandleGlowAnimationState();
}

class _HandleGlowAnimationState extends State<_HandleGlowAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 100 + (40 * _controller.value),
              height: 100 + (40 * _controller.value),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(
                    0xFF0052D1,
                  ).withValues(alpha: 0.3 * (1 - _controller.value)),
                  width: 2,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0052D1).withValues(alpha: 0.1),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Icon(
                Icons.pan_tool_alt_rounded,
                size: 48,
                color: const Color(0xFF0052D1),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CanopyZoomAnimation extends StatefulWidget {
  @override
  State<_CanopyZoomAnimation> createState() => _CanopyZoomAnimationState();
}

class _CanopyZoomAnimationState extends State<_CanopyZoomAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            Transform.scale(
              scale: 1.0 + (0.3 * _controller.value),
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: const Color(0xFF0052D1).withValues(alpha: 0.05),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const Icon(
              Icons.umbrella_rounded,
              size: 64,
              color: Color(0xFF0052D1),
            ),
          ],
        );
      },
    );
  }
}

class _ScanningLightOverlay extends StatefulWidget {
  @override
  State<_ScanningLightOverlay> createState() => _ScanningLightOverlayState();
}

class _ScanningLightOverlayState extends State<_ScanningLightOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Positioned(
          top: 40 + (100 * _controller.value),
          child: Container(
            width: 140,
            height: 2,
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0052D1).withValues(alpha: 0.8),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FrameHighlightAnimation extends StatefulWidget {
  @override
  State<_FrameHighlightAnimation> createState() =>
      _FrameHighlightAnimationState();
}

class _FrameHighlightAnimationState extends State<_FrameHighlightAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 130,
          height: 130,
          decoration: BoxDecoration(
            border: Border.all(
              color: const Color(
                0xFF0052D1,
              ).withValues(alpha: 0.5 * _controller.value),
              width: 3,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
        );
      },
    );
  }
}

class _DamageReportBottomSheet extends StatefulWidget {
  final Function(String) onReport;
  const _DamageReportBottomSheet({required this.onReport});

  @override
  State<_DamageReportBottomSheet> createState() =>
      _DamageReportBottomSheetState();
}

class _DamageReportBottomSheetState extends State<_DamageReportBottomSheet> {
  String? _selected;
  final List<String> _types = ["Tear", "Broken Handle", "Bent Frame", "Other"];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            "What happened?",
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ..._types.map(
            (t) => RadioListTile<String>(
              title: Text(t, style: GoogleFonts.outfit()),
              value: t,
              // ignore: deprecated_member_use
              groupValue: _selected,
              // ignore: deprecated_member_use
              onChanged: (v) => setState(() => _selected = v),
              activeColor: Colors.red,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _selected == null
                  ? null
                  : () => widget.onReport(_selected!),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text("Confirm Damage Report"),
            ),
          ),
        ],
      ),
    );
  }
}
