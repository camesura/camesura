import 'package:camesura/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('トップ画面にブランドと補正フローが表示される', (tester) async {
    await tester.pumpWidget(const CameSuraApp());

    expect(find.text('かめすら'), findsOneWidget);
    expect(find.text('姿勢を見る'), findsOneWidget);
    expect(find.text('条件を確認'), findsOneWidget);
    expect(find.text('向きを補正'), findsOneWidget);
    expect(find.text('補正をはじめる'), findsOneWidget);
  });

  testWidgets('補正をはじめると補正準備画面へ進む', (tester) async {
    await tester.pumpWidget(const CameSuraApp());

    await tester.tap(find.text('補正をはじめる'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('補正準備'), findsOneWidget);
    expect(find.byKey(const Key('pose-camera-view')), findsOneWidget);
    expect(find.byTooltip('Bridgeを探す'), findsOneWidget);
    expect(find.text('リセット'), findsOneWidget);
    expect(find.text('Yawリセット'), findsOneWidget);
  });
}
