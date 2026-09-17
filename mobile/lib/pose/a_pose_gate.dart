import 'a_pose_conditions.dart';

/// Aポーズ「成立と再待機」状態機械（camesura-spec.md 6.4）。
///
/// Flutterに依存しない純粋なDartクラス。`setup`（初回設定中）や監視停止中は
/// 呼び出し側が[update]自体を呼ばないことで表現する。
enum APoseGateState { watching, holding, sending, latched, error }

enum APoseGateAction { none, sendRequest }

class APoseGate {
  APoseGate({
    this.holdDuration = APoseThresholds.holdDuration,
    this.breakDuration = APoseThresholds.breakDuration,
  });

  final Duration holdDuration;
  final Duration breakDuration;

  APoseGateState _state = APoseGateState.watching;
  Duration? _metSince;
  Duration? _unmetSince;

  APoseGateState get state => _state;

  /// 保持できたAポーズの継続時間（送信時の`stable_ms`用）。
  Duration? _stableDurationAtSend;
  Duration? get lastStableDuration => _stableDurationAtSend;

  /// [holdDuration]までの残り時間。まだ保持を始めていない（`watching`で
  /// [allMet]がまだ一度もtrueになっていない）場合は[holdDuration]をそのまま
  /// 返す。UIのカウントダウン表示に使う。
  Duration remainingHold(Duration timestamp) {
    final metSince = _metSince;
    if (metSince == null) return holdDuration;
    final remaining = holdDuration - (timestamp - metSince);
    return remaining > Duration.zero ? remaining : Duration.zero;
  }

  /// 毎フレーム呼ぶ。[holdDuration]以上連続で[allMet]だった直後の1回だけ
  /// [APoseGateAction.sendRequest]を返し、内部状態を`sending`へ進める
  /// （ラッチが閉じ、以後は[completeSend]を呼ぶまで送信しない）。
  APoseGateAction update({required bool allMet, required Duration timestamp}) {
    switch (_state) {
      case APoseGateState.watching:
        return _updateWatching(allMet, timestamp);
      case APoseGateState.holding:
        return _updateWatching(allMet, timestamp);
      case APoseGateState.sending:
        return APoseGateAction.none;
      case APoseGateState.latched:
      case APoseGateState.error:
        _updateBreak(allMet, timestamp);
        return APoseGateAction.none;
    }
  }

  APoseGateAction _updateWatching(bool allMet, Duration timestamp) {
    if (!allMet) {
      _metSince = null;
      _state = APoseGateState.watching;
      return APoseGateAction.none;
    }
    _metSince ??= timestamp;
    final held = timestamp - _metSince!;
    if (held >= holdDuration) {
      _stableDurationAtSend = held;
      _state = APoseGateState.sending;
      _metSince = null;
      return APoseGateAction.sendRequest;
    }
    _state = APoseGateState.holding;
    return APoseGateAction.none;
  }

  void _updateBreak(bool allMet, Duration timestamp) {
    if (allMet) {
      _unmetSince = null;
      return;
    }
    _unmetSince ??= timestamp;
    if (timestamp - _unmetSince! >= breakDuration) {
      _unmetSince = null;
      _state = APoseGateState.watching;
    }
  }

  /// `sending`中にBridgeへの送信が完了した後に呼ぶ。成功・失敗どちらでも
  /// Aポーズが[breakDuration]連続で崩れるまで再送しない。
  void completeSend({required bool success}) {
    if (_state != APoseGateState.sending) return;
    _state = success ? APoseGateState.latched : APoseGateState.error;
  }
}
