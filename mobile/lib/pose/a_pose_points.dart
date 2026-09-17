import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'pose_skeleton_painter.dart';

/// Aポーズ判定に必須の12点。顔が画角に入っていなくても判定できるよう
/// 鼻は[optionalLandmarkTypes]として別扱いにする（実機フィードバックにより
/// フレーミング時に頭が切れても全身判定が通るようにした）。
const requiredLandmarkTypes = <PoseLandmarkType>[
  PoseLandmarkType.leftShoulder,
  PoseLandmarkType.rightShoulder,
  PoseLandmarkType.leftElbow,
  PoseLandmarkType.rightElbow,
  PoseLandmarkType.leftWrist,
  PoseLandmarkType.rightWrist,
  PoseLandmarkType.leftHip,
  PoseLandmarkType.rightHip,
  PoseLandmarkType.leftKnee,
  PoseLandmarkType.rightKnee,
  PoseLandmarkType.leftAnkle,
  PoseLandmarkType.rightAnkle,
];

/// 検出できれば正面判定の精度に使うが、欠けていても他の条件は判定できる点。
const optionalLandmarkTypes = <PoseLandmarkType>[PoseLandmarkType.nose];

/// ランドマーク1点。判定ロジックはこの値クラスだけに依存し、ML Kitの
/// [PoseLandmark]を直接扱わないため、テストでリテラルとして構築できる。
class PosePoint {
  const PosePoint({required this.x, required this.y, required this.likelihood});

  final double x;
  final double y;
  final double likelihood;
}

typedef PosePoints = Map<PoseLandmarkType, PosePoint>;

/// センサーの回転を反映したあとの、左上原点の正立画像サイズ（仕様6.3）。
Size uprightImageSize(Size imageSize, InputImageRotation rotation) {
  switch (rotation) {
    case InputImageRotation.rotation90deg:
    case InputImageRotation.rotation270deg:
      return Size(imageSize.height, imageSize.width);
    case InputImageRotation.rotation0deg:
    case InputImageRotation.rotation180deg:
      return imageSize;
  }
}

/// [frame]から必須12点を抜き出し、正立画像座標へ変換する。必須点が1つでも
/// 検出されていなければnull。鼻など[optionalLandmarkTypes]は検出できた
/// ときだけ追加され、欠けていても判定は継続できる。
///
/// 座標変換は骨格オーバーレイの描画で実機確認済みの[translatePosePoint]を
/// 再利用する。前面カメラの左右反転は肩幅・上下関係など本判定が使う
/// 幾何量には影響しないため、描画用と同じ変換をそのまま使える。
PosePoints? extractRequiredPoints(PoseFrame frame) {
  final upright = uprightImageSize(frame.imageSize, frame.rotation);
  final points = <PoseLandmarkType, PosePoint>{};

  PosePoint? translate(PoseLandmarkType type) {
    final landmark = frame.pose.landmarks[type];
    if (landmark == null) return null;
    final translated = translatePosePoint(
      x: landmark.x,
      y: landmark.y,
      canvasSize: upright,
      imageSize: frame.imageSize,
      rotation: frame.rotation,
      lensDirection: frame.lensDirection,
      isIOS: Platform.isIOS,
    );
    return PosePoint(
      x: translated.dx,
      y: translated.dy,
      likelihood: landmark.likelihood,
    );
  }

  for (final type in requiredLandmarkTypes) {
    final point = translate(type);
    if (point == null) return null;
    points[type] = point;
  }
  for (final type in optionalLandmarkTypes) {
    final point = translate(type);
    if (point != null) points[type] = point;
  }
  return points;
}

/// 必須点の信頼度の最小値（reset_requestの`confidence`、仕様7.2）。
/// オプション点（鼻）は含めない。
double? minRequiredLikelihood(PosePoints? points) {
  if (points == null) return null;
  var minValue = double.infinity;
  for (final type in requiredLandmarkTypes) {
    final point = points[type];
    if (point == null) return null;
    if (point.likelihood < minValue) minValue = point.likelihood;
  }
  return minValue;
}
