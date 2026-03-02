import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'home_page.dart';
import '../../services/database_service.dart';

class InspectionStep {
  final String title;
  final String tooltip;
  final IconData icon;

  InspectionStep({
    required this.title,
    required this.tooltip,
    required this.icon,
  });
}

class UmbrellaConditionVerificationPage extends StatefulWidget {
  final String userId;
  final String stationId;
  final String umbrellaId;
  final String transactionId;

  const UmbrellaConditionVerificationPage({
    super.key,
    required this.userId,
    required this.stationId,
    required this.umbrellaId,
    required this.transactionId,
  });

  @override
  State<UmbrellaConditionVerificationPage> createState() =>
      _UmbrellaConditionVerificationPageState();
}

class _UmbrellaConditionVerificationPageState
    extends State<UmbrellaConditionVerificationPage> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  Timer? _timer;

  final List<InspectionStep> _steps = [
    InspectionStep(
      title: "Check Handle & Grip",
      tooltip: "Ensure handle is sturdy and button works properly",
      icon: Icons.pan_tool_alt_rounded,
    ),
    InspectionStep(
      title: "Check Canopy Cloth",
      tooltip: "Check for tears, holes, or damage in fabric",
      icon: Icons.umbrella_rounded,
    ),
    InspectionStep(
      title: "Check Overall Frame",
      tooltip: "Ensure no bent ribs or broken frame",
      icon: Icons.grid_view_rounded,
    ),
  ];

  bool _checkedHandle = false;
  bool _checkedCanopy = false;
  bool _checkedFrame = false;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _startAutoPlay();
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
    _pageController.dispose();
    super.dispose();
  }

  bool get _isAllChecked => _checkedHandle && _checkedCanopy && _checkedFrame;

  Future<void> _handleConfirm() async {
    if (!_isAllChecked) return;
    setState(() => _isProcessing = true);

    // Simulate minor delay for professional feel
    await Future.delayed(const Duration(milliseconds: 800));

    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => const HomePage(initialIndex: 1),
        ),
        (route) => false,
      );
    }
  }

  void _showReportIssueSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) =>
          _ReportIssueBottomSheet(onReport: _handleReturnUmbrella),
    );
  }

  Future<void> _handleReturnUmbrella(String reason) async {
    setState(() => _isProcessing = true);
    try {
      await DatabaseService().returnUmbrella(
        transactionId: widget.transactionId,
        userId: widget.userId,
        stationId: widget.stationId,
        umbrellaId: widget.umbrellaId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Umbrella returned successfully: $reason"),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const HomePage()),
          (route) => false,
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
    return WillPopScope(
      onWillPop: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              "Cancel Verification?",
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
            ),
            content: Text(
              "Reporting damage after rental may result in deposit deduction.",
              style: GoogleFonts.outfit(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Continue"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Exit"),
              ),
            ],
          ),
        );
        return confirmed ?? false;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              _buildProgressHeader(),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildAnimationSection(),
                      _buildChecklistSection(),
                      _buildWarningCard(),
                      _buildReportButton(),
                    ],
                  ),
                ),
              ),
              _buildConfirmButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressHeader() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Verify Condition",
                style: GoogleFonts.outfit(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
              Text(
                "Ensure umbrella is in good shape",
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF0066FF).withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              widget.umbrellaId,
              style: GoogleFonts.outfit(
                color: const Color(0xFF0066FF),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimationSection() {
    return Column(
      children: [
        SizedBox(
          height: 250,
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (idx) => setState(() => _currentStep = idx),
            itemCount: _steps.length,
            itemBuilder: (context, index) {
              return _InspectionStepWidget(step: _steps[index], index: index);
            },
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            _steps.length,
            (index) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _currentStep == index
                    ? const Color(0xFF0066FF)
                    : Colors.grey[300],
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChecklistSection() {
    return Container(
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FD),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey[100]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Quick Inspection Checklist",
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 16),
          _buildCheckItem(
            "Handle & Grip sturdy",
            _checkedHandle,
            (v) => setState(() => _checkedHandle = v!),
          ),
          _buildCheckItem(
            "Canopy Cloth no holes",
            _checkedCanopy,
            (v) => setState(() => _checkedCanopy = v!),
          ),
          _buildCheckItem(
            "Overall Frame no bends",
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: value
            ? const Color(0xFF0066FF).withOpacity(0.05)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: CheckboxListTile(
        value: value,
        onChanged: (v) {
          HapticFeedback.lightImpact();
          onChanged(v);
        },
        title: Text(text, style: GoogleFonts.outfit(fontSize: 15)),
        controlAffinity: ListTileControlAffinity.leading,
        activeColor: const Color(0xFF0066FF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildWarningCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Colors.orange,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "If damage is reported after rental, deposit may be deducted.",
              style: GoogleFonts.outfit(
                fontSize: 12,
                color: Colors.orange[900],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: TextButton.icon(
        onPressed: _showReportIssueSheet,
        icon: const Icon(Icons.report_problem_outlined, size: 18),
        label: Text(
          "Report an issue instead",
          style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
        ),
        style: TextButton.styleFrom(foregroundColor: Colors.red),
      ),
    );
  }

  Widget _buildConfirmButton() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: (_isAllChecked && !_isProcessing) ? _handleConfirm : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0066FF),
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
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Confirm & Unlock",
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.lock_open_rounded, size: 20),
                  ],
                ),
        ),
      ),
    );
  }
}

class _InspectionStepWidget extends StatelessWidget {
  final InspectionStep step;
  final int index;
  const _InspectionStepWidget({required this.step, required this.index});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 800),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  _InspectionGlow(index: index),
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0066FF).withOpacity(0.05),
                      shape: BoxShape.circle,
                    ),
                    child: _buildAnimatedIcon(),
                  ),
                  if (index == 1) _buildScanningEffect(),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                step.title,
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  step.tooltip,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAnimatedIcon() {
    if (index == 0) {
      return _HandlePressAnimation(icon: step.icon);
    } else if (index == 1) {
      return _SlowRotationAnimation(icon: step.icon);
    }
    return Icon(step.icon, size: 64, color: const Color(0xFF0066FF));
  }

  Widget _buildScanningEffect() {
    return const _ScanningLightEffect();
  }
}

class _HandlePressAnimation extends StatefulWidget {
  final IconData icon;
  const _HandlePressAnimation({required this.icon});

  @override
  State<_HandlePressAnimation> createState() => _HandlePressAnimationState();
}

class _HandlePressAnimationState extends State<_HandlePressAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween(
        begin: 1.0,
        end: 0.85,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: Icon(widget.icon, size: 64, color: const Color(0xFF0066FF)),
    );
  }
}

class _SlowRotationAnimation extends StatefulWidget {
  final IconData icon;
  const _SlowRotationAnimation({required this.icon});

  @override
  State<_SlowRotationAnimation> createState() => _SlowRotationAnimationState();
}

class _SlowRotationAnimationState extends State<_SlowRotationAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: Icon(widget.icon, size: 64, color: const Color(0xFF0066FF)),
    );
  }
}

class _ScanningLightEffect extends StatefulWidget {
  const _ScanningLightEffect();

  @override
  State<_ScanningLightEffect> createState() => _ScanningLightEffectState();
}

class _ScanningLightEffectState extends State<_ScanningLightEffect>
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
        return Container(
          width: 130,
          height: 130,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withOpacity(0.0),
                const Color(
                  0xFF0066FF,
                ).withOpacity(0.2 * (1 - (_controller.value - 0.5).abs() * 2)),
                Colors.white.withOpacity(0.0),
              ],
              stops: [
                (_controller.value - 0.2).clamp(0.0, 1.0),
                _controller.value,
                (_controller.value + 0.2).clamp(0.0, 1.0),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InspectionGlow extends StatefulWidget {
  final int index;
  const _InspectionGlow({required this.index});

  @override
  State<_InspectionGlow> createState() => _InspectionGlowState();
}

class _InspectionGlowState extends State<_InspectionGlow>
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
        return Container(
          width: 140 + (20 * _controller.value),
          height: 140 + (20 * _controller.value),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(
                0xFF0066FF,
              ).withOpacity(0.3 * (1 - _controller.value)),
              width: 2,
            ),
          ),
        );
      },
    );
  }
}

class _ReportIssueBottomSheet extends StatefulWidget {
  final Function(String) onReport;
  const _ReportIssueBottomSheet({required this.onReport});

  @override
  State<_ReportIssueBottomSheet> createState() =>
      _ReportIssueBottomSheetState();
}

class _ReportIssueBottomSheetState extends State<_ReportIssueBottomSheet> {
  String? _selectedReason;
  final List<String> _reasons = [
    "Tear in cloth",
    "Broken handle",
    "Bent frame",
    "Other",
  ];

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
            "Report an Issue",
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "What seems to be the problem?",
            style: GoogleFonts.outfit(color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          ..._reasons.map(
            (reason) => RadioListTile<String>(
              title: Text(reason, style: GoogleFonts.outfit(fontSize: 16)),
              value: reason,
              groupValue: _selectedReason,
              onChanged: (v) => setState(() => _selectedReason = v),
              activeColor: Colors.red,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _selectedReason == null
                  ? null
                  : () => widget.onReport(_selectedReason!),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: Text(
                "Return Umbrella",
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
