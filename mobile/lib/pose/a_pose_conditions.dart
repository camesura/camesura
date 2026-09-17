import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'a_pose_points.dart';

/// Aポーズ判定の数値しきい値（camesura-spec.md 6.4）。実機映像で調整する
/// 場合はこのクラスだけを変更する。
class APoseThresholds {
  static const double minLikelihood = 0.6;
  static const double frontTiltRatio = 0.15;
  static const double uprightMinAngleDeg = 100;
  static const double uprightMaxTiltDeg = 45;
  static const double armMinAngleDeg = 140;
  static const double armOutwardMinDeg = 15;
  static const double armOutwardMaxDeg = 65;
  static const double armAngleDiffMaxDeg = 25;
  static const Duration stillWindow = Duration(seconds: 1);
  static const double stillMaxNormalizedMovement = 0.08;
  static const Duration holdDuration = Duration(seconds: 2);
  static const Duration breakDuration = Duration(seconds: 1);
}

/// 1フレームのAポーズ条件判定結果。
class APoseConditions {
  const APoseConditions({
    required this.fullBody,
    required this.frontFacing,
    required this.upright,
    required this.arms,
    required this.still,
  });

  static const none = APoseConditions(
    fullBody: false,
    frontFacing: false,
    upright: false,
    arms: false,
    still: false,
  );

  final bool fullBody;
  final bool frontFacing;
  final bool upright;
  final bool arms;
  final bool still;

  /// 「ポーズ自体が要件を満たしているか」（静止を除く）。この条件が
  /// 満たされた時点でプレビュー枠を緑にし、「静止してください」と案内する。
  /// 直立は検出精度（卓上設置で下半身が画角外になる等）に対して厳しすぎる
  /// ため、一旦ゲートから外す。全身/直立/腕は引き続き画面表示の参考情報。
  bool get poseMatched => frontFacing;

  /// キャリブレーション（自動Yaw Reset送信）の実際のゲート条件。
  /// ポーズが要件を満たした状態のまま静止していることを条件にする。
  bool get allMet => poseMatched && still;
}

/// [points]と正立画像サイズ[imageSize]からAポーズ条件を判定する。
/// `still`は時間履歴が必要なため呼び出し側（[APoseStabilityTracker]）が
/// 判定した結果をそのまま渡す。
APoseConditions evaluateAPoseConditions({
  required PosePoints? points,
  required Size imageSize,
  required bool still,
}) {
  if (points == null) return APoseConditions.none;
  return APoseConditions(
    fullBody: _checkFullBody(points, imageSize),
    frontFacing: _checkFrontFacing(points),
    upright: _checkUpright(points, imageSize),
    arms: _checkArms(points),
    still: still,
  );
}

/// 信頼度が十分にあり、画像範囲内にある点か。机の上に固定して足元が
/// 画角外になる場合など、ML Kitが低信頼度・画面外の推測座標を返す点を
/// そのまま角度計算に使わないためのガード。
bool _isValidPoint(PosePoint point, Size imageSize) {
  if (point.likelihood < APoseThresholds.minLikelihood) return false;
  if (point.x < 0 || point.x > imageSize.width) return false;
  if (point.y < 0 || point.y > imageSize.height) return false;
  return true;
}

bool _checkFullBody(PosePoints points, Size imageSize) {
  // 鼻（顔）はオプション点なので、画角に入っていなくても全身判定には
  // 影響させない。必須12点だけを確認する。
  for (final type in requiredLandmarkTypes) {
    final point = points[type];
    if (point == null || !_isValidPoint(point, imageSize)) return false;
  }
  return true;
}

bool _checkFrontFacing(PosePoints points) {
  final leftShoulder = points[PoseLandmarkType.leftShoulder]!;
  final rightShoulder = points[PoseLandmarkType.rightShoulder]!;
  final leftHip = points[PoseLandmarkType.leftHip]!;
  final rightHip = points[PoseLandmarkType.rightHip]!;

  // 鼻が検出できているときだけ「両肩の間にあるか」を確認する。顔が
  // 画角外で検出されていない場合はこのチェックをスキップする。
  final nose = points[PoseLandmarkType.nose];
  if (nose != null) {
    final minShoulderX = math.min(leftShoulder.x, rightShoulder.x);
    final maxShoulderX = math.max(leftShoulder.x, rightShoulder.x);
    if (nose.x < minShoulderX || nose.x > maxShoulderX) return false;
  }

  final shoulderWidth = _dist(leftShoulder, rightShoulder);
  if ((leftShoulder.y - rightShoulder.y).abs() >
      APoseThresholds.frontTiltRatio * shoulderWidth) {
    return false;
  }

  final hipWidth = _dist(leftHip, rightHip);
  if ((leftHip.y - rightHip.y).abs() >
      APoseThresholds.frontTiltRatio * hipWidth) {
    return false;
  }
  return true;
}

bool _checkUpright(PosePoints points, Size imageSize) {
  final leftHip = points[PoseLandmarkType.leftHip]!;
  final rightHip = points[PoseLandmarkType.rightHip]!;
  final leftKnee = points[PoseLandmarkType.leftKnee]!;
  final rightKnee = points[PoseLandmarkType.rightKnee]!;
  final leftAnkle = points[PoseLandmarkType.leftAnkle]!;
  final rightAnkle = points[PoseLandmarkType.rightAnkle]!;
  final leftShoulder = points[PoseLandmarkType.leftShoulder]!;
  final rightShoulder = points[PoseLandmarkType.rightShoulder]!;

  // 卓上設置などで太もも・足首が画角外になると、ML Kitは低信頼度・
  // 画面外の推測座標を返す。その座標で角度を計算して見かけ上
  // 「直立」になってしまうのを防ぐ。
  for (final point in [
    leftHip,
    rightHip,
    leftKnee,
    rightKnee,
    leftAnkle,
    rightAnkle,
    leftShoulder,
    rightShoulder,
  ]) {
    if (!_isValidPoint(point, imageSize)) return false;
  }

  if (_angleAtVertex(leftHip, leftKnee, leftAnkle) <
      APoseThresholds.uprightMinAngleDeg) {
    return false;
  }
  if (_angleAtVertex(rightHip, rightKnee, rightAnkle) <
      APoseThresholds.uprightMinAngleDeg) {
    return false;
  }

  final shoulderMidX = (leftShoulder.x + rightShoulder.x) / 2;
  final shoulderMidY = (leftShoulder.y + rightShoulder.y) / 2;
  final hipMidX = (leftHip.x + rightHip.x) / 2;
  final hipMidY = (leftHip.y + rightHip.y) / 2;

  if (shoulderMidY >= hipMidY) return false;

  final tiltDeg = _angleFromVerticalDown(
    hipMidX - shoulderMidX,
    hipMidY - shoulderMidY,
  );
  return tiltDeg <= APoseThresholds.uprightMaxTiltDeg;
}

bool _checkArms(PosePoints points) {
  final leftShoulder = points[PoseLandmarkType.leftShoulder]!;
  final rightShoulder = points[PoseLandmarkType.rightShoulder]!;
  final leftElbow = points[PoseLandmarkType.leftElbow]!;
  final rightElbow = points[PoseLandmarkType.rightElbow]!;
  final leftWrist = points[PoseLandmarkType.leftWrist]!;
  final rightWrist = points[PoseLandmarkType.rightWrist]!;

  if (_angleAtVertex(leftShoulder, leftElbow, leftWrist) <
      APoseThresholds.armMinAngleDeg) {
    return false;
  }
  if (_angleAtVertex(rightShoulder, rightElbow, rightWrist) <
      APoseThresholds.armMinAngleDeg) {
    return false;
  }

  if (leftWrist.y <= leftShoulder.y || rightWrist.y <= rightShoulder.y) {
    return false;
  }

  final shoulderMidX = (leftShoulder.x + rightShoulder.x) / 2;

  final leftOutwardSign = leftShoulder.x >= shoulderMidX ? 1 : -1;
  if (!_isOutward(
    leftShoulder,
    leftElbow,
    leftWrist,
    shoulderMidX,
    leftOutwardSign,
  )) {
    return false;
  }
  final rightOutwardSign = rightShoulder.x >= shoulderMidX ? 1 : -1;
  if (!_isOutward(
    rightShoulder,
    rightElbow,
    rightWrist,
    shoulderMidX,
    rightOutwardSign,
  )) {
    return false;
  }

  final leftTiltDeg = _angleFromVerticalDown(
    leftWrist.x - leftShoulder.x,
    leftWrist.y - leftShoulder.y,
  );
  final rightTiltDeg = _angleFromVerticalDown(
    rightWrist.x - rightShoulder.x,
    rightWrist.y - rightShoulder.y,
  );
  if (leftTiltDeg < APoseThresholds.armOutwardMinDeg ||
      leftTiltDeg > APoseThresholds.armOutwardMaxDeg) {
    return false;
  }
  if (rightTiltDeg < APoseThresholds.armOutwardMinDeg ||
      rightTiltDeg > APoseThresholds.armOutwardMaxDeg) {
    return false;
  }
  return (leftTiltDeg - rightTiltDeg).abs() <=
      APoseThresholds.armAngleDiffMaxDeg;
}

/// 肩→肘→手首の順で、体の中心線からの距離が単調に大きくなっているか
/// （手首は肘より外側、肘は肩より外側）。
bool _isOutward(
  PosePoint shoulder,
  PosePoint elbow,
  PosePoint wrist,
  double centerX,
  int outwardSign,
) {
  final shoulderOffset = (shoulder.x - centerX) * outwardSign;
  final elbowOffset = (elbow.x - centerX) * outwardSign;
  final wristOffset = (wrist.x - centerX) * outwardSign;
  return elbowOffset > shoulderOffset && wristOffset > elbowOffset;
}

double _dist(PosePoint a, PosePoint b) {
  final dx = a.x - b.x;
  final dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy);
}

/// bを頂点とする角度(度)。
double _angleAtVertex(PosePoint a, PosePoint b, PosePoint c) {
  final v1x = a.x - b.x;
  final v1y = a.y - b.y;
  final v2x = c.x - b.x;
  final v2y = c.y - b.y;
  final mag1 = math.sqrt(v1x * v1x + v1y * v1y);
  final mag2 = math.sqrt(v2x * v2x + v2y * v2y);
  if (mag1 == 0 || mag2 == 0) return 0;
  final cosTheta = ((v1x * v2x + v1y * v2y) / (mag1 * mag2)).clamp(-1.0, 1.0);
  return math.acos(cosTheta) * 180 / math.pi;
}

/// ベクトル(dx, dy)（y下向き正）と鉛直下向き(0, 1)との角度(度)。
double _angleFromVerticalDown(double dx, double dy) {
  final mag = math.sqrt(dx * dx + dy * dy);
  if (mag == 0) return 0;
  final cosTheta = (dy / mag).clamp(-1.0, 1.0);
  return math.acos(cosTheta) * 180 / math.pi;
}
