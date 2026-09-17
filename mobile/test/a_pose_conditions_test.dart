import 'package:camesura/pose/a_pose_conditions.dart';
import 'package:camesura/pose/a_pose_points.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

const _imageSize = Size(1080, 1920);

PosePoints _basePoints() => {
  PoseLandmarkType.nose: const PosePoint(x: 540, y: 300, likelihood: 0.9),
  PoseLandmarkType.leftShoulder: const PosePoint(
    x: 620,
    y: 400,
    likelihood: 0.9,
  ),
  PoseLandmarkType.rightShoulder: const PosePoint(
    x: 460,
    y: 400,
    likelihood: 0.9,
  ),
  PoseLandmarkType.leftElbow: const PosePoint(
    x: 716.45,
    y: 514.9,
    likelihood: 0.9,
  ),
  PoseLandmarkType.rightElbow: const PosePoint(
    x: 363.55,
    y: 514.9,
    likelihood: 0.9,
  ),
  PoseLandmarkType.leftWrist: const PosePoint(
    x: 812.9,
    y: 629.8,
    likelihood: 0.9,
  ),
  PoseLandmarkType.rightWrist: const PosePoint(
    x: 267.1,
    y: 629.8,
    likelihood: 0.9,
  ),
  PoseLandmarkType.leftHip: const PosePoint(x: 600, y: 800, likelihood: 0.9),
  PoseLandmarkType.rightHip: const PosePoint(x: 480, y: 800, likelihood: 0.9),
  PoseLandmarkType.leftKnee: const PosePoint(x: 600, y: 1200, likelihood: 0.9),
  PoseLandmarkType.rightKnee: const PosePoint(x: 480, y: 1200, likelihood: 0.9),
  PoseLandmarkType.leftAnkle: const PosePoint(x: 600, y: 1600, likelihood: 0.9),
  PoseLandmarkType.rightAnkle: const PosePoint(
    x: 480,
    y: 1600,
    likelihood: 0.9,
  ),
};

PosePoints _override(PosePoints base, PoseLandmarkType type, PosePoint point) {
  final copy = Map<PoseLandmarkType, PosePoint>.of(base);
  copy[type] = point;
  return copy;
}

void main() {
  group('evaluateAPoseConditions - 基準ポーズ', () {
    test('全条件を満たす', () {
      final result = evaluateAPoseConditions(
        points: _basePoints(),
        imageSize: _imageSize,
        still: true,
      );
      expect(result.fullBody, isTrue);
      expect(result.frontFacing, isTrue);
      expect(result.upright, isTrue);
      expect(result.arms, isTrue);
      expect(result.still, isTrue);
      expect(result.allMet, isTrue);
    });

    test('pointsがnullなら全条件false', () {
      final result = evaluateAPoseConditions(
        points: null,
        imageSize: _imageSize,
        still: true,
      );
      expect(result.allMet, isFalse);
      expect(result.still, isFalse);
    });
  });

  group('全身', () {
    test('信頼度が0.6未満なら不成立', () {
      final points = _override(
        _basePoints(),
        PoseLandmarkType.leftShoulder,
        const PosePoint(x: 620, y: 400, likelihood: 0.59),
      );
      final result = evaluateAPoseConditions(
        points: points,
        imageSize: _imageSize,
        still: true,
      );
      // fullBodyは参考情報であり、キャリブレーションの成立条件
      // （allMet）は正面+静止だけを見るため信頼度不足の影響を受けない。
      expect(result.fullBody, isFalse);
    });

    test('画像範囲外なら不成立', () {
      final points = _override(
        _basePoints(),
        PoseLandmarkType.leftAnkle,
        const PosePoint(x: 600, y: 2000, likelihood: 0.9),
      );
      final result = evaluateAPoseConditions(
        points: points,
        imageSize: _imageSize,
        still: true,
      );
      expect(result.fullBody, isFalse);
    });
  });

  group('正面', () {
    test('鼻が両肩の間から外れると不成立', () {
      final points = _override(
        _basePoints(),
        PoseLandmarkType.nose,
        const PosePoint(x: 700, y: 300, likelihood: 0.9),
      );
      final result = evaluateAPoseConditions(
        points: points,
        imageSize: _imageSize,
        still: true,
      );
      expect(result.frontFacing, isFalse);
    });

    test('肩の高さの差が肩幅の15%を超えると不成立', () {
      final base = _basePoints();
      final points = _override(
        base,
        PoseLandmarkType.leftShoulder,
        PosePoint(
          x: base[PoseLandmarkType.leftShoulder]!.x,
          y: base[PoseLandmarkType.leftShoulder]!.y + 30,
          likelihood: 0.9,
        ),
      );
      final result = evaluateAPoseConditions(
        points: points,
        imageSize: _imageSize,
        still: true,
      );
      expect(result.frontFacing, isFalse);
    });
  });

  group('直立', () {
    test('膝を曲げると不成立', () {
      final points = _override(
        _basePoints(),
        PoseLandmarkType.leftKnee,
        const PosePoint(x: 750, y: 1000, likelihood: 0.9),
      );
      final result = evaluateAPoseConditions(
        points: points,
        imageSize: _imageSize,
        still: true,
      );
      expect(result.upright, isFalse);
    });

    test('肩の中点が腰の中点より下だと不成立', () {
      final base = _basePoints();
      final points = _override(
        base,
        PoseLandmarkType.leftShoulder,
        PosePoint(
          x: base[PoseLandmarkType.leftShoulder]!.x,
          y: 1300,
          likelihood: 0.9,
        ),
      );
      final result = evaluateAPoseConditions(
        points: points,
        imageSize: _imageSize,
        still: true,
      );
      expect(result.upright, isFalse);
    });
  });

  group('腕', () {
    test('肘を曲げると不成立', () {
      final points = _override(
        _basePoints(),
        PoseLandmarkType.leftElbow,
        const PosePoint(x: 750, y: 400, likelihood: 0.9),
      );
      final result = evaluateAPoseConditions(
        points: points,
        imageSize: _imageSize,
        still: true,
      );
      expect(result.arms, isFalse);
    });

    test('腕が鉛直に近すぎる（15度未満）と不成立', () {
      final points = _override(
        _override(
          _basePoints(),
          PoseLandmarkType.leftElbow,
          const PosePoint(x: 640, y: 514.9, likelihood: 0.9),
        ),
        PoseLandmarkType.leftWrist,
        const PosePoint(x: 660, y: 629.8, likelihood: 0.9),
      );
      final result = evaluateAPoseConditions(
        points: points,
        imageSize: _imageSize,
        still: true,
      );
      expect(result.arms, isFalse);
    });

    test('手首が肩より上だと不成立', () {
      final points = _override(
        _basePoints(),
        PoseLandmarkType.leftWrist,
        const PosePoint(x: 812.9, y: 350, likelihood: 0.9),
      );
      final result = evaluateAPoseConditions(
        points: points,
        imageSize: _imageSize,
        still: true,
      );
      expect(result.arms, isFalse);
    });

    test('左右の腕角度の差が25度を超えると不成立', () {
      // 右手を鉛直方向により近づけ、左右差を25度以上にする。
      final points = _override(
        _override(
          _basePoints(),
          PoseLandmarkType.rightElbow,
          const PosePoint(x: 440, y: 514.9, likelihood: 0.9),
        ),
        PoseLandmarkType.rightWrist,
        const PosePoint(x: 420, y: 629.8, likelihood: 0.9),
      );
      final result = evaluateAPoseConditions(
        points: points,
        imageSize: _imageSize,
        still: true,
      );
      expect(result.arms, isFalse);
    });
  });

  test('鼻（顔）が検出されていなくても全条件を満たせる', () {
    final base = _basePoints();
    final withoutNose = Map<PoseLandmarkType, PosePoint>.of(base)
      ..remove(PoseLandmarkType.nose);
    final result = evaluateAPoseConditions(
      points: withoutNose,
      imageSize: _imageSize,
      still: true,
    );
    expect(result.fullBody, isTrue);
    expect(result.frontFacing, isTrue);
    expect(result.allMet, isTrue);
  });

  test('stillがfalseならallMetもfalse', () {
    final result = evaluateAPoseConditions(
      points: _basePoints(),
      imageSize: _imageSize,
      still: false,
    );
    expect(result.fullBody, isTrue);
    expect(result.frontFacing, isTrue);
    expect(result.upright, isTrue);
    expect(result.arms, isTrue);
    expect(result.still, isFalse);
    expect(result.allMet, isFalse);
  });

  test('直立・腕を満たしていなくても正面+静止だけでallMetになる', () {
    // 膝を曲げて直立を崩し、肘も曲げて腕の条件を崩す。
    final points = _override(
      _override(
        _basePoints(),
        PoseLandmarkType.leftKnee,
        const PosePoint(x: 750, y: 1000, likelihood: 0.9),
      ),
      PoseLandmarkType.leftElbow,
      const PosePoint(x: 750, y: 400, likelihood: 0.9),
    );
    final result = evaluateAPoseConditions(
      points: points,
      imageSize: _imageSize,
      still: true,
    );
    expect(result.upright, isFalse);
    expect(result.arms, isFalse);
    expect(result.frontFacing, isTrue);
    expect(result.still, isTrue);
    expect(result.allMet, isTrue);
  });
}
