import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'bridge_client.dart';
import 'bridge_discovery.dart';
import 'bridge_settings.dart';

enum _BridgeState { unchecked, available, unreachable }

enum _ResetPhase { idle, countdown, sending, finished, failed }

/// Bridge connection settings and manual Full/Yaw Reset buttons with countdown.
class BridgeResetPanel extends StatefulWidget {
  const BridgeResetPanel({
    super.key,
    this.client = const BridgeClient(),
    this.discovery = const BridgeDiscovery(),
    this.autoConnect = true,
  });

  final BridgeClient client;
  final BridgeDiscovery discovery;

  /// Checks the saved Bridge on open. A full LAN sweep is intentionally only
  /// started by the user so it cannot compete with live pose detection.
  final bool autoConnect;

  @override
  State<BridgeResetPanel> createState() => _BridgeResetPanelState();
}

class _BridgeResetPanelState extends State<BridgeResetPanel> {
  BridgeSettings? _settings;
  _BridgeState _bridgeState = _BridgeState.unchecked;
  _ResetPhase _resetPhase = _ResetPhase.idle;
  ResetKind? _activeKind;
  String? _adapter;
  String? _resultMessage;
  bool _isChecking = false;
  bool _isSearching = false;
  int _secondsLeft = 0;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSettings());
  }

  Future<void> _loadSettings() async {
    final settings = await BridgeSettings.load();
    if (!mounted) return;
    setState(() => _settings = settings);
    if (!widget.autoConnect) return;
    if (settings.host.isNotEmpty) await _checkConnection();
  }

  /// Finds Bridges on the LAN. One result is selected automatically; several
  /// are offered in a list. [interactive] also reports "not found".
  Future<void> _searchBridges({required bool interactive}) async {
    final settings = _settings;
    if (settings == null || _isSearching) return;
    setState(() => _isSearching = true);
    DiscoveryResult result;
    try {
      result = await widget.discovery.discover();
    } on Exception {
      result = const DiscoveryResult(bridges: [], networks: []);
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
    if (!mounted) return;

    final bridges = result.bridges;
    DiscoveredBridge? selected;
    if (bridges.length == 1) {
      selected = bridges.single;
    } else if (bridges.length > 1) {
      selected = await showDialog<DiscoveredBridge>(
        context: context,
        builder: (_) => _BridgePickerDialog(bridges: bridges),
      );
    } else if (interactive) {
      final searched = result.networks.isEmpty
          ? '探索できるネットワークがありません'
          : '探索: ${result.networks.join(', ')}';
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            'Bridgeが見つかりません（$searched）。'
            'PCでBridgeを起動し、同じWi-Fiに接続してください',
          ),
        ),
      );
    }
    if (selected == null || !mounted) return;

    final updated = await settings.withHost(selected.host);
    if (!mounted) return;
    setState(() {
      _settings = updated;
      _bridgeState = _BridgeState.available;
      _adapter = selected!.adapter;
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _editHost() async {
    final settings = _settings;
    if (settings == null) return;
    final host = await showDialog<String>(
      context: context,
      builder: (_) => _HostDialog(initialHost: settings.host),
    );
    if (host == null || !mounted) return;
    final updated = await settings.withHost(host);
    if (!mounted) return;
    setState(() {
      _settings = updated;
      _bridgeState = _BridgeState.unchecked;
      _adapter = null;
    });
    await _checkConnection();
  }

  Future<void> _checkConnection() async {
    final host = _settings?.host ?? '';
    if (host.isEmpty || _isChecking) return;
    setState(() => _isChecking = true);
    try {
      final response = await widget.client.ping(host);
      if (!mounted) return;
      setState(() {
        _bridgeState = _BridgeState.available;
        _adapter = response.adapter;
      });
    } on Exception {
      if (!mounted) return;
      setState(() => _bridgeState = _BridgeState.unreachable);
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  void _startCountdown(ResetKind kind) {
    final settings = _settings;
    if (settings == null) return;
    if (settings.host.isEmpty) {
      unawaited(_searchBridges(interactive: true));
      return;
    }
    _countdownTimer?.cancel();
    setState(() {
      _resetPhase = _ResetPhase.countdown;
      _activeKind = kind;
      _secondsLeft = manualResetCountdown.inSeconds;
      _resultMessage = null;
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      if (_secondsLeft > 1) {
        setState(() => _secondsLeft--);
        return;
      }
      timer.cancel();
      unawaited(_sendReset(settings, kind));
    });
  }

  Future<void> _sendReset(BridgeSettings settings, ResetKind kind) async {
    setState(() => _resetPhase = _ResetPhase.sending);
    try {
      final response = await widget.client.requestReset(
        kind: kind,
        host: settings.host,
        deviceId: settings.deviceId,
        pose: 'manual',
        stableMs: manualResetCountdown.inMilliseconds,
        confidence: 0,
      );
      if (!mounted) return;
      setState(() {
        _bridgeState = _BridgeState.available;
        _adapter = response.adapter;
        _resetPhase = response.isOk ? _ResetPhase.finished : _ResetPhase.failed;
        _resultMessage = response.isOk
            ? '${_kindLabel(kind)}が完了しました'
            : _errorText(response.code, response.message);
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _bridgeState = _BridgeState.unreachable;
        _resetPhase = _ResetPhase.failed;
        _resultMessage = error.toString();
      });
    }
  }

  String _kindLabel(ResetKind kind) => switch (kind) {
    ResetKind.full => 'リセット',
    ResetKind.yaw => 'Yawリセット',
  };

  String _buttonLabel(ResetKind kind) {
    if (_activeKind != kind) return _kindLabel(kind);
    return switch (_resetPhase) {
      _ResetPhase.countdown => '$_secondsLeft秒後',
      _ResetPhase.sending => '送信中…',
      _ => _kindLabel(kind),
    };
  }

  String _errorText(String code, String message) {
    return switch (code) {
      'cooldown' => '少し待ってからもう一度押してください',
      'slimevr_unavailable' => 'SlimeVR Serverに接続できません',
      'slimevr_timeout' => 'SlimeVR Serverが応答しません',
      _ => 'リセットに失敗しました（$code: $message）',
    };
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final host = settings?.host ?? '';
    final busy =
        _resetPhase == _ResetPhase.countdown ||
        _resetPhase == _ResetPhase.sending;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDDE8EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.router_rounded, color: _bridgeColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isSearching
                          ? 'Bridge  探しています…'
                          : _isChecking
                          ? 'Bridge  確認中…'
                          : 'Bridge  $_bridgeLabel',
                      style: const TextStyle(
                        color: Color(0xFF284950),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      host.isEmpty
                          ? '未選択'
                          : '$host:$bridgeDefaultPort'
                                '${_adapter == null ? '' : '（$_adapter）'}',
                      style: const TextStyle(color: Color(0xFF557177)),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Bridgeを探す',
                onPressed: settings == null || busy || _isSearching
                    ? null
                    : () => _searchBridges(interactive: true),
                icon: _isSearching
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search_rounded),
              ),
              IconButton(
                tooltip: 'IPアドレスを設定',
                onPressed: settings == null || busy ? null : _editHost,
                icon: const Icon(Icons.edit_rounded),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: settings == null || busy
                      ? null
                      : () => _startCountdown(ResetKind.full),
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: Text(_buttonLabel(ResetKind.full)),
                  style: _resetButtonStyle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: settings == null || busy
                      ? null
                      : () => _startCountdown(ResetKind.yaw),
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: Text(_buttonLabel(ResetKind.yaw)),
                  style: _resetButtonStyle,
                ),
              ),
            ],
          ),
          if (_resultMessage case final message?) ...[
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _resetPhase == _ResetPhase.finished
                    ? AppColors.turtleGreenDark
                    : const Color(0xFFB3261E),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static final _resetButtonStyle = FilledButton.styleFrom(
    minimumSize: const Size.fromHeight(52),
    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
  );

  String get _bridgeLabel => switch (_bridgeState) {
    _BridgeState.unchecked => '接続未確認',
    _BridgeState.available => '利用可能',
    _BridgeState.unreachable => '応答なし',
  };

  Color get _bridgeColor => switch (_bridgeState) {
    _BridgeState.unchecked => const Color(0xFF718A90),
    _BridgeState.available => AppColors.turtleGreenDark,
    _BridgeState.unreachable => const Color(0xFFB3261E),
  };
}

class _BridgePickerDialog extends StatelessWidget {
  const _BridgePickerDialog({required this.bridges});

  final List<DiscoveredBridge> bridges;

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Bridgeを選択'),
      children: [
        for (final bridge in bridges)
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(bridge),
            child: ListTile(
              leading: const Icon(Icons.computer_rounded),
              title: Text(bridge.name),
              subtitle: Text(bridge.host),
            ),
          ),
      ],
    );
  }
}

class _HostDialog extends StatefulWidget {
  const _HostDialog({required this.initialHost});

  final String initialHost;

  @override
  State<_HostDialog> createState() => _HostDialogState();
}

class _HostDialogState extends State<_HostDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialHost,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final host = _controller.text.trim();
    if (host.isEmpty) return;
    Navigator.of(context).pop(host);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('BridgeのIPアドレス'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          hintText: '192.168.0.10',
          helperText: 'Bridge起動時にPCへ表示されるアドレス',
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}
