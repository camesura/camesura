import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

const bridgeProtocolVersion = 1;
const bridgeDefaultPort = 39500;

/// Countdown before a manual reset, matching SlimeVR's default delay.
const manualResetCountdown = Duration(seconds: 3);

enum ResetKind {
  full('full'),
  yaw('yaw');

  const ResetKind(this.wireName);

  final String wireName;
}

class BridgeResponse {
  const BridgeResponse({
    required this.type,
    required this.status,
    required this.code,
    required this.adapter,
    required this.message,
  });

  factory BridgeResponse.fromJson(Map<String, Object?> json) {
    return BridgeResponse(
      type: json['type'] as String? ?? '',
      status: json['status'] as String? ?? '',
      code: json['code'] as String? ?? '',
      adapter: json['adapter'] as String? ?? '',
      message: json['message'] as String? ?? '',
    );
  }

  final String type;
  final String status;
  final String code;
  final String adapter;
  final String message;

  bool get isOk => status == 'ok';
}

class BridgeException implements Exception {
  const BridgeException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BridgeClient {
  const BridgeClient({
    this.port = bridgeDefaultPort,
    this.sendCount = 3,
    this.sendInterval = const Duration(milliseconds: 100),
    this.responseTimeout = const Duration(seconds: 2),
  });

  final int port;
  final int sendCount;
  final Duration sendInterval;
  final Duration responseTimeout;

  Future<BridgeResponse> ping(String host) {
    return _exchange(host, {
      'version': bridgeProtocolVersion,
      'type': 'ping',
      'request_id': newRequestId(),
    });
  }

  Future<BridgeResponse> requestReset({
    required ResetKind kind,
    required String host,
    required String deviceId,
    required String pose,
    required int stableMs,
    required double confidence,
  }) {
    return _exchange(host, {
      'version': bridgeProtocolVersion,
      'type': 'reset_request',
      'request_id': newRequestId(),
      'device_id': deviceId,
      'reset': kind.wireName,
      'pose': pose,
      'stable_ms': stableMs,
      'confidence': confidence,
    });
  }

  Future<BridgeResponse> _exchange(
    String host,
    Map<String, Object?> message,
  ) async {
    final address = InternetAddress.tryParse(host.trim());
    if (address == null || address.type != InternetAddressType.IPv4) {
      throw const BridgeException('IPアドレスの形式が正しくありません');
    }
    final requestId = message['request_id'];
    final payload = utf8.encode(jsonEncode(message));

    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final response = Completer<BridgeResponse>();
    final subscription = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      if (datagram == null || response.isCompleted) return;
      try {
        final json = jsonDecode(utf8.decode(datagram.data));
        if (json is Map<String, Object?> && json['request_id'] == requestId) {
          response.complete(BridgeResponse.fromJson(json));
        }
      } on FormatException {
        // Ignore unrelated or broken datagrams and keep waiting.
      }
    });

    var closed = false;
    unawaited(() async {
      for (var i = 0; i < sendCount; i++) {
        if (i > 0) await Future<void>.delayed(sendInterval);
        if (closed || response.isCompleted) return;
        try {
          socket.send(payload, address, port);
        } on SocketException catch (error) {
          if (!response.isCompleted) {
            response.completeError(
              BridgeException('送信できませんでした: ${error.message}'),
            );
          }
          return;
        }
      }
    }());

    try {
      return await response.future.timeout(
        responseTimeout,
        onTimeout: () => throw const BridgeException('Bridgeから応答がありません'),
      );
    } finally {
      closed = true;
      await subscription.cancel();
      socket.close();
    }
  }
}

final _random = Random.secure();

/// Returns a random UUID v4 string.
String newRequestId() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
