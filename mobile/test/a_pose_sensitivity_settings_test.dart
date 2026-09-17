import 'package:camesura/pose/a_pose_sensitivity_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('デフォルト値は実機で確認した正面80%・静止0%になっている', () {
    const settings = APoseSensitivitySettings.defaultSettings;
    expect(settings.frontStrictness, 0.8);
    expect(settings.stillnessStrictness, 0.0);
    expect(settings.frontTiltRatio, closeTo(0.096, 1e-9));
    expect(settings.stillMaxNormalizedMovement, closeTo(0.13, 1e-9));
  });

  test('厳しさ1.0で最も厳しいしきい値になる', () {
    const settings = APoseSensitivitySettings(
      frontStrictness: 1.0,
      stillnessStrictness: 1.0,
    );
    expect(settings.frontTiltRatio, closeTo(0.06, 1e-9));
    expect(settings.stillMaxNormalizedMovement, closeTo(0.03, 1e-9));
  });

  test('厳しさ0.0で最も緩いしきい値になる', () {
    const settings = APoseSensitivitySettings(
      frontStrictness: 0.0,
      stillnessStrictness: 0.0,
    );
    expect(settings.frontTiltRatio, closeTo(0.24, 1e-9));
    expect(settings.stillMaxNormalizedMovement, closeTo(0.13, 1e-9));
  });

  test('loadは保存前はデフォルト値を返す', () async {
    final settings = await APoseSensitivitySettings.load();
    expect(settings.frontStrictness, 0.8);
    expect(settings.stillnessStrictness, 0.0);
  });

  test(
    'withFrontStrictness/withStillnessStrictnessで保存した値がloadで復元される',
    () async {
      final loaded = await APoseSensitivitySettings.load();
      final updated = await loaded.withFrontStrictness(0.8);
      final updated2 = await updated.withStillnessStrictness(0.2);

      expect(updated2.frontStrictness, 0.8);
      expect(updated2.stillnessStrictness, 0.2);

      final reloaded = await APoseSensitivitySettings.load();
      expect(reloaded.frontStrictness, 0.8);
      expect(reloaded.stillnessStrictness, 0.2);
    },
  );
}
