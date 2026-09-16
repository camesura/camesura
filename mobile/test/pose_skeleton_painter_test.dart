import 'package:camera/camera.dart';
import 'package:camesura/pose/pose_skeleton_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

void main() {
  const imageSize = Size(1280, 720);
  const portraitCanvas = Size(360, 640);

  test('Androidの90度回転画像を縦向きプレビューへ変換する', () {
    final point = translatePosePoint(
      x: 360,
      y: 640,
      canvasSize: portraitCanvas,
      imageSize: imageSize,
      rotation: InputImageRotation.rotation90deg,
      lensDirection: CameraLensDirection.back,
      isIOS: false,
    );

    expect(point, const Offset(180, 320));
  });

  test('270度回転ではX座標を反転する', () {
    final point = translatePosePoint(
      x: 180,
      y: 320,
      canvasSize: portraitCanvas,
      imageSize: imageSize,
      rotation: InputImageRotation.rotation270deg,
      lensDirection: CameraLensDirection.back,
      isIOS: false,
    );

    expect(point, const Offset(270, 160));
  });

  test('回転なしの前面カメラではX座標を鏡像化する', () {
    final point = translatePosePoint(
      x: 320,
      y: 180,
      canvasSize: const Size(640, 360),
      imageSize: imageSize,
      rotation: InputImageRotation.rotation0deg,
      lensDirection: CameraLensDirection.front,
      isIOS: false,
    );

    expect(point, const Offset(480, 90));
  });
}
