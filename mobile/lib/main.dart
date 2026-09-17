import 'dart:async';

import 'package:flutter/material.dart';

import 'bridge/bridge_reset_panel.dart';
import 'bridge/bridge_settings.dart';
import 'camera/pose_camera_view.dart';
import 'pose/a_pose_sensitivity_settings.dart';
import 'theme/app_colors.dart';

void main() {
  runApp(const CameSuraApp());
}

class CameSuraApp extends StatelessWidget {
  const CameSuraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'かめすら',
      theme: ThemeData(
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: AppColors.turtleGreen,
              brightness: Brightness.light,
            ).copyWith(
              secondary: AppColors.slimeBlue,
              tertiary: AppColors.slimeBlue,
            ),
        scaffoldBackgroundColor: const Color(0xFFF3F7F8),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _BrandHeader(),
                  const SizedBox(height: 28),
                  const _HeroPanel(),
                  const SizedBox(height: 18),
                  const _PrivacyNote(),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const CalibrationPage(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.center_focus_strong_rounded),
                    label: const Text('補正をはじめる'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      textStyle: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CalibrationPage extends StatefulWidget {
  const CalibrationPage({super.key});

  @override
  State<CalibrationPage> createState() => _CalibrationPageState();
}

class _CalibrationPageState extends State<CalibrationPage> {
  BridgeSettings? _settings;
  APoseSensitivitySettings _sensitivity =
      APoseSensitivitySettings.defaultSettings;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSettings());
  }

  Future<void> _loadSettings() async {
    final settings = await BridgeSettings.load();
    final sensitivity = await APoseSensitivitySettings.load();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _sensitivity = sensitivity;
    });
  }

  Future<void> _openSensitivitySettings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SensitivitySettingsSheet(
        sensitivity: _sensitivity,
        onChanged: (updated) {
          if (mounted) setState(() => _sensitivity = updated);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '補正準備',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: const Color(0xFFF3F7F8),
        actions: [
          IconButton(
            tooltip: '判定の厳しさを調整',
            onPressed: _openSensitivitySettings,
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 姿勢チェックの条件は正面のみで、成立するとPoseCameraView
                  // 内部でカメラ枠が緑に光る。ここでは条件を文字やチップで
                  // 明示しない。
                  PoseCameraView(
                    settings: _settings,
                    sensitivity: _sensitivity,
                  ),
                  const SizedBox(height: 18),
                  if (_settings != null) const BridgeResetPanel(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SensitivitySettingsSheet extends StatefulWidget {
  const _SensitivitySettingsSheet({
    required this.sensitivity,
    required this.onChanged,
  });

  final APoseSensitivitySettings sensitivity;
  final ValueChanged<APoseSensitivitySettings> onChanged;

  @override
  State<_SensitivitySettingsSheet> createState() =>
      _SensitivitySettingsSheetState();
}

class _SensitivitySettingsSheetState extends State<_SensitivitySettingsSheet> {
  late APoseSensitivitySettings _current = widget.sensitivity;

  void _updateFront(double value) {
    final updated = APoseSensitivitySettings(
      frontStrictness: value,
      stillnessStrictness: _current.stillnessStrictness,
    );
    setState(() => _current = updated);
    widget.onChanged(updated);
  }

  void _updateStillness(double value) {
    final updated = APoseSensitivitySettings(
      frontStrictness: _current.frontStrictness,
      stillnessStrictness: value,
    );
    setState(() => _current = updated);
    widget.onChanged(updated);
  }

  Future<void> _persistFront(double value) async {
    final saved = await _current.withFrontStrictness(value);
    if (mounted) setState(() => _current = saved);
  }

  Future<void> _persistStillness(double value) async {
    final saved = await _current.withStillnessStrictness(value);
    if (mounted) setState(() => _current = saved);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '判定の厳しさ',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: const Color(0xFF082C36),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '緩めるとポーズが成立しやすくなり、厳しくすると誤作動しにくくなります',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: const Color(0xFF557177)),
            ),
            const SizedBox(height: 20),
            _SensitivitySlider(
              label: '正面判定',
              value: _current.frontStrictness,
              onChanged: _updateFront,
              onChangeEnd: _persistFront,
            ),
            const SizedBox(height: 16),
            _SensitivitySlider(
              label: '静止判定',
              value: _current.stillnessStrictness,
              onChanged: _updateStillness,
              onChangeEnd: _persistStillness,
            ),
          ],
        ),
      ),
    );
  }
}

class _SensitivitySlider extends StatelessWidget {
  const _SensitivitySlider({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF284950),
            fontWeight: FontWeight.w700,
          ),
        ),
        Slider(
          value: value,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
          activeColor: AppColors.turtleGreen,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Text('緩い', style: TextStyle(color: Color(0xFF718A90))),
            Text('厳しい', style: TextStyle(color: Color(0xFF718A90))),
          ],
        ),
      ],
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: const Color(0xFFDDE8EA)),
          ),
          child: Image.asset('assets/icon/icon_foreground.png'),
        ),
        const SizedBox(width: 13),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'かめすら',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: const Color(0xFF082C36),
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            Text(
              'POSE-GUIDED YAW RESET',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: const Color(0xFF557177),
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.turtleGreenDark, AppColors.slimeBlueDark],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x24082C36),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            '正しい姿勢で、ズレをリセット。',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'スマホが姿勢を見守り、補正のタイミングを案内します',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: const Color(0xFFB7CED3), height: 1.5),
          ),
          const SizedBox(height: 28),
          const _HowItWorksGraphic(),
          const SizedBox(height: 22),
          const _BeforeAfterStrip(),
        ],
      ),
    );
  }
}

class _HowItWorksGraphic extends StatelessWidget {
  const _HowItWorksGraphic();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(
          child: _FlowStep(
            icon: Icons.accessibility_new_rounded,
            label: '姿勢を見る',
          ),
        ),
        _FlowArrow(),
        Expanded(
          child: _FlowStep(icon: Icons.fact_check_rounded, label: '条件を確認'),
        ),
        _FlowArrow(),
        Expanded(
          child: _FlowStep(
            icon: Icons.explore_rounded,
            label: '向きを補正',
            highlighted: true,
          ),
        ),
      ],
    );
  }
}

class _FlowStep extends StatelessWidget {
  const _FlowStep({
    required this.icon,
    required this.label,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final color = highlighted ? AppColors.turtleGreen : AppColors.slimeBlue;

    return Column(
      children: [
        Container(
          width: 64,
          height: 74,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            border: Border.all(color: color.withValues(alpha: 0.52)),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(icon, color: color, size: 34),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: const Color(0xFFDCE9EB),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _FlowArrow extends StatelessWidget {
  const _FlowArrow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 28),
      child: Icon(
        Icons.arrow_forward_rounded,
        size: 20,
        color: Color(0xFF64858C),
      ),
    );
  }
}

class _BeforeAfterStrip extends StatelessWidget {
  const _BeforeAfterStrip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Row(
        children: [
          Expanded(
            child: _PoseState(
              icon: Icons.rotate_left_rounded,
              color: Color(0xFFFF9B8E),
              title: '方位がズレる',
              isGood: false,
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Icon(Icons.chevron_right_rounded, color: Color(0xFF88A3A8)),
          ),
          Expanded(
            child: _PoseState(
              icon: Icons.check_circle_rounded,
              color: AppColors.turtleGreen,
              title: '正しくリセット',
              isGood: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _PoseState extends StatelessWidget {
  const _PoseState({
    required this.icon,
    required this.color,
    required this.title,
    required this.isGood,
  });

  final IconData icon;
  final Color color;
  final String title;
  final bool isGood;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, color: color, size: 34),
            if (!isGood)
              Transform.rotate(
                angle: -0.18,
                child: const Icon(
                  Icons.accessibility_new_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
          ],
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDDE8EA)),
      ),
      child: const Row(
        children: [
          Icon(Icons.phonelink_lock_rounded, color: AppColors.slimeBlue),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'カメラ映像は端末内だけで処理されます',
              style: TextStyle(
                color: Color(0xFF284950),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
