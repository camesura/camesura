import 'package:camesura/pose/a_pose_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('allMetがfalseの間はwatchingのままnoneを返す', () {
    final gate = APoseGate(
      holdDuration: const Duration(seconds: 2),
      breakDuration: const Duration(seconds: 1),
    );
    expect(
      gate.update(allMet: false, timestamp: Duration.zero),
      APoseGateAction.none,
    );
    expect(gate.state, APoseGateState.watching);
  });

  test('holdDuration未満ではsendRequestを返さない', () {
    final gate = APoseGate(
      holdDuration: const Duration(seconds: 2),
      breakDuration: const Duration(seconds: 1),
    );
    gate.update(allMet: true, timestamp: Duration.zero);
    final action = gate.update(
      allMet: true,
      timestamp: const Duration(milliseconds: 1999),
    );
    expect(action, APoseGateAction.none);
    expect(gate.state, APoseGateState.holding);
  });

  test('holdDuration継続したら1回だけsendRequestを返しsendingへ進む', () {
    final gate = APoseGate(
      holdDuration: const Duration(seconds: 2),
      breakDuration: const Duration(seconds: 1),
    );
    gate.update(allMet: true, timestamp: Duration.zero);
    final action = gate.update(
      allMet: true,
      timestamp: const Duration(seconds: 2),
    );
    expect(action, APoseGateAction.sendRequest);
    expect(gate.state, APoseGateState.sending);

    // sending中は継続してallMet=trueでもnoneのまま（ラッチが閉じている）。
    final duringSend = gate.update(
      allMet: true,
      timestamp: const Duration(milliseconds: 2100),
    );
    expect(duringSend, APoseGateAction.none);
    expect(gate.state, APoseGateState.sending);
  });

  test('姿勢が途中で崩れるとholdの計測がリセットされる', () {
    final gate = APoseGate(
      holdDuration: const Duration(seconds: 2),
      breakDuration: const Duration(seconds: 1),
    );
    gate.update(allMet: true, timestamp: Duration.zero);
    gate.update(allMet: false, timestamp: const Duration(milliseconds: 500));
    expect(gate.state, APoseGateState.watching);

    gate.update(allMet: true, timestamp: const Duration(milliseconds: 600));
    final tooEarly = gate.update(
      allMet: true,
      timestamp: const Duration(milliseconds: 2500),
    );
    expect(tooEarly, APoseGateAction.none);

    final action = gate.update(
      allMet: true,
      timestamp: const Duration(milliseconds: 2600),
    );
    expect(action, APoseGateAction.sendRequest);
  });

  test('送信成功後はAポーズが1秒連続で崩れるまで再送しない', () {
    final gate = APoseGate(
      holdDuration: const Duration(seconds: 2),
      breakDuration: const Duration(seconds: 1),
    );
    gate.update(allMet: true, timestamp: Duration.zero);
    gate.update(allMet: true, timestamp: const Duration(seconds: 2));
    gate.completeSend(success: true);
    expect(gate.state, APoseGateState.latched);

    // 姿勢を保ち続けても再送しない。
    expect(
      gate.update(allMet: true, timestamp: const Duration(milliseconds: 2100)),
      APoseGateAction.none,
    );
    expect(gate.state, APoseGateState.latched);

    // 崩れてから1秒未満ではまだwatchingに戻らない。
    gate.update(allMet: false, timestamp: const Duration(milliseconds: 2200));
    gate.update(allMet: false, timestamp: const Duration(milliseconds: 3199));
    expect(gate.state, APoseGateState.latched);

    // 1秒連続で崩れたらwatchingへ戻り、再度holdできる。
    gate.update(allMet: false, timestamp: const Duration(milliseconds: 3200));
    expect(gate.state, APoseGateState.watching);

    gate.update(allMet: true, timestamp: const Duration(milliseconds: 3200));
    final action = gate.update(
      allMet: true,
      timestamp: const Duration(milliseconds: 5200),
    );
    expect(action, APoseGateAction.sendRequest);
  });

  test('送信失敗時もerror状態から同じ規則で再送を待つ', () {
    final gate = APoseGate(
      holdDuration: const Duration(seconds: 2),
      breakDuration: const Duration(seconds: 1),
    );
    gate.update(allMet: true, timestamp: Duration.zero);
    gate.update(allMet: true, timestamp: const Duration(seconds: 2));
    gate.completeSend(success: false);
    expect(gate.state, APoseGateState.error);

    gate.update(allMet: false, timestamp: const Duration(milliseconds: 2200));
    gate.update(allMet: false, timestamp: const Duration(milliseconds: 3200));
    expect(gate.state, APoseGateState.watching);
  });

  test('lastStableDurationは送信を要求した時点の保持時間を返す', () {
    final gate = APoseGate(
      holdDuration: const Duration(seconds: 2),
      breakDuration: const Duration(seconds: 1),
    );
    gate.update(allMet: true, timestamp: Duration.zero);
    gate.update(allMet: true, timestamp: const Duration(milliseconds: 2180));
    expect(gate.lastStableDuration, const Duration(milliseconds: 2180));
  });
}
