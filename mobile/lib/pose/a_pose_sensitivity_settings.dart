import 'package:shared_preferences/shared_preferences.dart';

/// 正面・静止判定の厳しさをスマホから調整するための永続化設定。
///
/// `frontStrictness`/`stillnessStrictness`は0.0（緩い）〜1.0（厳しい）の
/// スライダー値で、実際のしきい値（[frontTiltRatio]/[stillMaxNormalizedMovement]）
/// へ変換して使う。
class APoseSensitivitySettings {
  const APoseSensitivitySettings({
    required this.frontStrictness,
    required this.stillnessStrictness,
  });

  /// 実機で「ちょうど良かった」と確認できた値（正面80%・静止0%）を初期値にする。
  static const defaultSettings = APoseSensitivitySettings(
    frontStrictness: 0.8,
    stillnessStrictness: 0.0,
  );

  static const _frontStrictnessKey = 'apose_front_strictness';
  static const _stillnessStrictnessKey = 'apose_stillness_strictness';

  static const _frontTiltRatioMin = 0.06;
  static const _frontTiltRatioMax = 0.24;
  static const _stillMovementMin = 0.03;
  static const _stillMovementMax = 0.13;

  /// 0.0（緩い）〜1.0（厳しい）。正面判定（鼻・肩・腰の水平さ）の厳しさ。
  final double frontStrictness;

  /// 0.0（緩い）〜1.0（厳しい）。静止判定（手ブレ等の許容量）の厳しさ。
  final double stillnessStrictness;

  /// `_checkFrontFacing`が使う許容比率。厳しいほど小さくなる。
  double get frontTiltRatio => _lerpStrictness(
    min: _frontTiltRatioMin,
    max: _frontTiltRatioMax,
    strictness: frontStrictness,
  );

  /// `APoseStabilityTracker`が使う正規化移動量のしきい値。厳しいほど小さくなる。
  double get stillMaxNormalizedMovement => _lerpStrictness(
    min: _stillMovementMin,
    max: _stillMovementMax,
    strictness: stillnessStrictness,
  );

  static Future<APoseSensitivitySettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return APoseSensitivitySettings(
      frontStrictness:
          prefs.getDouble(_frontStrictnessKey) ??
          defaultSettings.frontStrictness,
      stillnessStrictness:
          prefs.getDouble(_stillnessStrictnessKey) ??
          defaultSettings.stillnessStrictness,
    );
  }

  Future<APoseSensitivitySettings> withFrontStrictness(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_frontStrictnessKey, value);
    return APoseSensitivitySettings(
      frontStrictness: value,
      stillnessStrictness: stillnessStrictness,
    );
  }

  Future<APoseSensitivitySettings> withStillnessStrictness(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_stillnessStrictnessKey, value);
    return APoseSensitivitySettings(
      frontStrictness: frontStrictness,
      stillnessStrictness: value,
    );
  }
}

double _lerpStrictness({
  required double min,
  required double max,
  required double strictness,
}) {
  return max - strictness.clamp(0.0, 1.0) * (max - min);
}
