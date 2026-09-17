import 'dart:math' as math;

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'a_pose_conditions.dart';
import 'a_pose_points.dart';

/// Aポーズ「静止」条件（camesura-spec.md 6.4）の判定器。
///
/// 時刻は呼び出し側が単調増加する[Duration]として渡す（フレーム数ではない）。
/// 必須点が欠損したフレームでは窓をリセットする。
class APoseStabilityTracker {
  APoseStabilityTracker({
    this.window = APoseThresholds.stillWindow,
    this.maxNormalizedMovement = APoseThresholds.stillMaxNormalizedMovement,
  });

  final Duration window;

  /// 静止判定の厳しさ。実行中に書き換え可能（設定画面のスライダーから
  /// その場で反映するため）。ウィンドウのリセットは不要。
  double maxNormalizedMovement;

  final List<(Duration timestamp, PosePoints points)> _samples = [];

  /// [points]がnull（必須点欠損）ならfalseを返し窓をリセットする。
  /// それ以外は直近[window]内の各点の最大移動距離を肩幅で正規化し、
  /// 13点平均が[maxNormalizedMovement]未満ならtrueを返す。
  bool addSample({required Duration timestamp, required PosePoints? points}) {
    if (points == null) {
      reset();
      return false;
    }

    _samples.add((timestamp, points));
    _samples.removeWhere((sample) => timestamp - sample.$1 > window);

    if (_samples.length < 2) return false;

    final shoulderWidth = _distance(
      points[PoseLandmarkType.leftShoulder]!,
      points[PoseLandmarkType.rightShoulder]!,
    );
    if (shoulderWidth <= 0) return false;

    var totalNormalizedMovement = 0.0;
    for (final type in requiredLandmarkTypes) {
      var maxMovement = 0.0;
      for (var i = 0; i < _samples.length; i++) {
        for (var j = i + 1; j < _samples.length; j++) {
          final movement = _distance(
            _samples[i].$2[type]!,
            _samples[j].$2[type]!,
          );
          if (movement > maxMovement) maxMovement = movement;
        }
      }
      totalNormalizedMovement += maxMovement / shoulderWidth;
    }
    final average = totalNormalizedMovement / requiredLandmarkTypes.length;
    return average < maxNormalizedMovement;
  }

  void reset() => _samples.clear();
}

double _distance(PosePoint a, PosePoint b) {
  final dx = a.x - b.x;
  final dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy);
}
