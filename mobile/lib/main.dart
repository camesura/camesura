import 'dart:async';

import 'package:flutter/material.dart';

import 'bridge/bridge_reset_panel.dart';
import 'bridge/bridge_settings.dart';
import 'camera/pose_camera_view.dart';
import 'pose/a_pose_conditions.dart';

void main() {
  runApp(const CameSuraApp());
}

class CameSuraApp extends StatelessWidget {
  const CameSuraApp({super.key});

  @override
  Widget build(BuildContext context) {
    const brandColor = Color(0xFF00AFC1);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'かめすら',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: brandColor,
          brightness: Brightness.light,
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
  APoseConditions _conditions = APoseConditions.none;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSettings());
  }

  Future<void> _loadSettings() async {
    final settings = await BridgeSettings.load();
    if (mounted) setState(() => _settings = settings);
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
                  PoseCameraView(
                    settings: _settings,
                    onConditionsChanged: (conditions, _) {
                      if (mounted) setState(() => _conditions = conditions);
                    },
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '姿勢チェック',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: const Color(0xFF082C36),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _ConditionChip(label: '全身', met: _conditions.fullBody),
                      _ConditionChip(label: '正面', met: _conditions.frontFacing),
                      _ConditionChip(label: '直立', met: _conditions.upright),
                      _ConditionChip(label: '腕', met: _conditions.arms),
                      _ConditionChip(label: '静止', met: _conditions.still),
                    ],
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

class _ConditionChip extends StatelessWidget {
  const _ConditionChip({required this.label, required this.met});

  final String label;
  final bool met;

  @override
  Widget build(BuildContext context) {
    final color = met ? const Color(0xFF007C4F) : const Color(0xFF718A90);
    return Chip(
      avatar: Icon(
        met ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
        size: 18,
        color: color,
      ),
      label: Text(label),
      side: BorderSide(
        color: met ? const Color(0xFF54E1A7) : const Color(0xFFD6E3E5),
      ),
      backgroundColor: met ? const Color(0xFFE8F8F0) : Colors.white,
      labelStyle: TextStyle(
        color: const Color(0xFF284950),
        fontWeight: FontWeight.w700,
      ),
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
          decoration: BoxDecoration(
            color: const Color(0xFF082C36),
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Icon(
            Icons.videocam_rounded,
            color: Color(0xFF54E1D3),
            size: 28,
          ),
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
          colors: [Color(0xFF0B3540), Color(0xFF061F28)],
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
    final color = highlighted
        ? const Color(0xFF54E1A7)
        : const Color(0xFF54D7E1);

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
              color: Color(0xFF54E1A7),
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
          Icon(Icons.phonelink_lock_rounded, color: Color(0xFF007C89)),
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
