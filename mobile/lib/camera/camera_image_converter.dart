import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

const _deviceOrientations = <DeviceOrientation, int>{
  DeviceOrientation.portraitUp: 0,
  DeviceOrientation.landscapeLeft: 90,
  DeviceOrientation.portraitDown: 180,
  DeviceOrientation.landscapeRight: 270,
};

class ConvertedCameraImage {
  const ConvertedCameraImage({
    required this.inputImage,
    required this.imageSize,
    required this.rotation,
  });

  final InputImage inputImage;
  final Size imageSize;
  final InputImageRotation rotation;
}

/// Converts a live camera frame into the byte layout expected by ML Kit.
///
/// The camera controller must use NV21 on Android and BGRA8888 on iOS.
ConvertedCameraImage? convertCameraImage({
  required CameraImage image,
  required CameraDescription camera,
  required DeviceOrientation deviceOrientation,
}) {
  InputImageRotation? rotation;
  if (Platform.isIOS) {
    rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation);
  } else if (Platform.isAndroid) {
    var rotationCompensation = _deviceOrientations[deviceOrientation];
    if (rotationCompensation == null) return null;

    if (camera.lensDirection == CameraLensDirection.front) {
      rotationCompensation =
          (camera.sensorOrientation + rotationCompensation) % 360;
    } else {
      rotationCompensation =
          (camera.sensorOrientation - rotationCompensation + 360) % 360;
    }
    rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
  }
  if (rotation == null) return null;

  final format = InputImageFormatValue.fromRawValue(image.format.raw);
  final isSupportedFormat =
      (Platform.isAndroid && format == InputImageFormat.nv21) ||
      (Platform.isIOS && format == InputImageFormat.bgra8888);
  if (!isSupportedFormat || image.planes.length != 1) return null;

  final plane = image.planes.first;
  final imageSize = Size(image.width.toDouble(), image.height.toDouble());
  final inputImage = InputImage.fromBytes(
    bytes: plane.bytes,
    metadata: InputImageMetadata(
      size: imageSize,
      rotation: rotation,
      format: format!,
      bytesPerRow: plane.bytesPerRow,
    ),
  );

  return ConvertedCameraImage(
    inputImage: inputImage,
    imageSize: imageSize,
    rotation: rotation,
  );
}
