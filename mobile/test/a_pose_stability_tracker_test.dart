import 'package:camesura/pose/a_pose_points.dart';
import 'package:camesura/pose/a_pose_stability_tracker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// 全13点を原点から(dx, dy)だけ平行移動した点群。肩幅は160。
PosePoints _shiftedPoints(double dx, double dy) {
  const base = {
    PoseLandmarkType.nose: (0.0, -300.0),
    PoseLandmarkType.leftShoulder: (80.0, -200.0),
    PoseLandmarkType.rightShoulder: (-80.0, -200.0),
    PoseLandmarkType.leftElbow: (120.0, -100.0),
    PoseLandmarkType.rightElbow: (-120.0, -100.0),
    PoseLandmarkType.leftWrist: (150.0, 0.0),
    PoseLandmarkType.rightWrist: (-150.0, 0.0),
    PoseLandmarkType.leftHip: (60.0, 100.0),
    PoseLandmarkType.rightHip: (-60.0, 100.0),
    PoseLandmarkType.leftKnee: (60.0, 300.0),
    PoseLandmarkType.rightKnee: (-60.0, 300.0),
    PoseLandmarkType.leftAnkle: (60.0, 500.0),
    PoseLandmarkType.rightAnkle: (-60.0, 500.0),
  };
  return base.map(
    (type, offset) => MapEntry(
      type,
      PosePoint(x: offset.$1 + dx, y: offset.$2 + dy, likelihood: 0.9),
    ),
  );
}

void main() {
  test('サンプルが1個だけでは判定できない（false）', () {
    final tracker = APoseStabilityTracker();
    expect(
      tracker.addSample(timestamp: Duration.zero, points: _shiftedPoints(0, 0)),
      isFalse,
    );
  });

  test('肩幅の3%未満の動きなら静止と判定する', () {
    final tracker = APoseStabilityTracker();
    tracker.addSample(timestamp: Duration.zero, points: _shiftedPoints(0, 0));
    // shoulderWidth=160, 移動4px -> normalized=0.025 < 0.03
    final result = tracker.addSample(
      timestamp: const Duration(milliseconds: 100),
      points: _shiftedPoints(4, 0),
    );
    expect(result, isTrue);
  });

  test('肩幅の8%以上動くと静止と判定しない', () {
    final tracker = APoseStabilityTracker();
    tracker.addSample(timestamp: Duration.zero, points: _shiftedPoints(0, 0));
    // shoulderWidth=160, 移動20px -> normalized=0.125 >= 0.08
    final result = tracker.addSample(
      timestamp: const Duration(milliseconds: 100),
      points: _shiftedPoints(20, 0),
    );
    expect(result, isFalse);
  });

  test('窓より古いサンプルは移動距離の計算から除外される', () {
    final tracker = APoseStabilityTracker();
    // 大きく動いた古いサンプル（1秒より前に押し出される）。
    tracker.addSample(timestamp: Duration.zero, points: _shiftedPoints(0, 0));
    final unstable = tracker.addSample(
      timestamp: const Duration(milliseconds: 50),
      points: _shiftedPoints(500, 0),
    );
    expect(unstable, isFalse);

    // t=0のサンプルは(1049-0)>1000msなので窓から外れる。
    // 残るt=50とt=1049の移動はわずか1pxなので静止と判定される。
    final stable = tracker.addSample(
      timestamp: const Duration(milliseconds: 1049),
      points: _shiftedPoints(500, 1),
    );
    expect(stable, isTrue);
  });

  test('maxNormalizedMovementを実行中に変更すると以降の判定に反映される', () {
    final tracker = APoseStabilityTracker();
    tracker.addSample(timestamp: Duration.zero, points: _shiftedPoints(0, 0));
    final strict = tracker.addSample(
      timestamp: const Duration(milliseconds: 100),
      points: _shiftedPoints(20, 0),
    );
    // shoulderWidth=160, 移動20px -> normalized=0.125 は既定値0.08以上で不成立。
    expect(strict, isFalse);

    tracker.maxNormalizedMovement = 0.2;
    final lenient = tracker.addSample(
      timestamp: const Duration(milliseconds: 200),
      points: _shiftedPoints(20, 0),
    );
    // 同じ0.125の動きでも、しきい値を0.2まで緩めれば成立する。
    expect(lenient, isTrue);
  });

  test('必須点が欠損すると窓がリセットされる', () {
    final tracker = APoseStabilityTracker();
    tracker.addSample(timestamp: Duration.zero, points: _shiftedPoints(0, 0));
    tracker.addSample(
      timestamp: const Duration(milliseconds: 50),
      points: _shiftedPoints(500, 0),
    );

    final reset = tracker.addSample(
      timestamp: const Duration(milliseconds: 60),
      points: null,
    );
    expect(reset, isFalse);

    // リセット後は新しい窓として1個目のサンプルからやり直す。
    final afterResetFirst = tracker.addSample(
      timestamp: const Duration(milliseconds: 100),
      points: _shiftedPoints(0, 0),
    );
    expect(afterResetFirst, isFalse);

    final afterResetSecond = tracker.addSample(
      timestamp: const Duration(milliseconds: 110),
      points: _shiftedPoints(0, 0),
    );
    expect(afterResetSecond, isTrue);
  });
}
