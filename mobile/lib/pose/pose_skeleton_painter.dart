import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

const double minimumLandmarkLikelihood = 0.5;

class PoseFrame {
  const PoseFrame({
    required this.pose,
    required this.imageSize,
    required this.rotation,
    required this.lensDirection,
  });

  final Pose pose;
  final Size imageSize;
  final InputImageRotation rotation;
  final CameraLensDirection lensDirection;
}

class PoseSkeletonPainter extends CustomPainter {
  const PoseSkeletonPainter(this.frame);

  final PoseFrame frame;

  static const _leftConnections = <(PoseLandmarkType, PoseLandmarkType)>[
    (PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow),
    (PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist),
    (PoseLandmarkType.leftWrist, PoseLandmarkType.leftIndex),
    (PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip),
    (PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee),
    (PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle),
    (PoseLandmarkType.leftAnkle, PoseLandmarkType.leftHeel),
    (PoseLandmarkType.leftHeel, PoseLandmarkType.leftFootIndex),
  ];

  static const _rightConnections = <(PoseLandmarkType, PoseLandmarkType)>[
    (PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow),
    (PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist),
    (PoseLandmarkType.rightWrist, PoseLandmarkType.rightIndex),
    (PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip),
    (PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee),
    (PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle),
    (PoseLandmarkType.rightAnkle, PoseLandmarkType.rightHeel),
    (PoseLandmarkType.rightHeel, PoseLandmarkType.rightFootIndex),
  ];

  static const _centerConnections = <(PoseLandmarkType, PoseLandmarkType)>[
    (PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder),
    (PoseLandmarkType.leftHip, PoseLandmarkType.rightHip),
    (PoseLandmarkType.nose, PoseLandmarkType.leftEye),
    (PoseLandmarkType.nose, PoseLandmarkType.rightEye),
    (PoseLandmarkType.leftEye, PoseLandmarkType.leftEar),
    (PoseLandmarkType.rightEye, PoseLandmarkType.rightEar),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final leftPaint = _linePaint(const Color(0xFF54E1A7));
    final rightPaint = _linePaint(const Color(0xFF54D7E1));
    final centerPaint = _linePaint(Colors.white.withValues(alpha: 0.92));
    final pointPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white;

    _drawConnections(canvas, size, _leftConnections, leftPaint);
    _drawConnections(canvas, size, _rightConnections, rightPaint);
    _drawConnections(canvas, size, _centerConnections, centerPaint);

    for (final landmark in frame.pose.landmarks.values) {
      if (landmark.likelihood < minimumLandmarkLikelihood) continue;
      final position = _translate(landmark, size);
      canvas.drawCircle(position, 4.5, pointPaint);
      canvas.drawCircle(position, 7, centerPaint..strokeWidth = 2);
    }
  }

  Paint _linePaint(Color color) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4
    ..strokeCap = StrokeCap.round
    ..color = color;

  void _drawConnections(
    Canvas canvas,
    Size size,
    List<(PoseLandmarkType, PoseLandmarkType)> connections,
    Paint paint,
  ) {
    for (final connection in connections) {
      final start = frame.pose.landmarks[connection.$1];
      final end = frame.pose.landmarks[connection.$2];
      if (start == null ||
          end == null ||
          start.likelihood < minimumLandmarkLikelihood ||
          end.likelihood < minimumLandmarkLikelihood) {
        continue;
      }
      canvas.drawLine(_translate(start, size), _translate(end, size), paint);
    }
  }

  Offset _translate(PoseLandmark landmark, Size canvasSize) {
    return translatePosePoint(
      x: landmark.x,
      y: landmark.y,
      canvasSize: canvasSize,
      imageSize: frame.imageSize,
      rotation: frame.rotation,
      lensDirection: frame.lensDirection,
      isIOS: Platform.isIOS,
    );
  }

  @override
  bool shouldRepaint(covariant PoseSkeletonPainter oldDelegate) {
    return oldDelegate.frame != frame;
  }
}

/// 生のランドマーク座標（センサー空間）を、回転・前面カメラの反転を
/// 反映した表示/判定用の座標へ変換する。[PoseSkeletonPainter]の描画と
/// `a_pose_points.dart`の判定用座標抽出の両方から使われる共有ロジック。
Offset translatePosePoint({
  required double x,
  required double y,
  required Size canvasSize,
  required Size imageSize,
  required InputImageRotation rotation,
  required CameraLensDirection lensDirection,
  required bool isIOS,
}) {
  switch (rotation) {
    case InputImageRotation.rotation90deg:
      return Offset(
        x * canvasSize.width / (isIOS ? imageSize.width : imageSize.height),
        y * canvasSize.height / (isIOS ? imageSize.height : imageSize.width),
      );
    case InputImageRotation.rotation270deg:
      return Offset(
        canvasSize.width -
            x * canvasSize.width / (isIOS ? imageSize.width : imageSize.height),
        y * canvasSize.height / (isIOS ? imageSize.height : imageSize.width),
      );
    case InputImageRotation.rotation0deg:
    case InputImageRotation.rotation180deg:
      final translatedX = x * canvasSize.width / imageSize.width;
      return Offset(
        lensDirection == CameraLensDirection.back
            ? translatedX
            : canvasSize.width - translatedX,
        y * canvasSize.height / imageSize.height,
      );
  }
}
