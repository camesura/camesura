import 'dart:convert';
import 'dart:io';

import 'package:camesura/bridge/bridge_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late RawDatagramSocket fakeBridge;
  late List<Map<String, Object?>> received;

  setUp(() async {
    received = [];
    fakeBridge = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() => fakeBridge.close());

  void replyWith(Map<String, Object?> Function(Map<String, Object?>) reply) {
    fakeBridge.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = fakeBridge.receive();
      if (datagram == null) return;
      final request =
          jsonDecode(utf8.decode(datagram.data)) as Map<String, Object?>;
      received.add(request);
      fakeBridge.send(
        utf8.encode(jsonEncode(reply(request))),
        datagram.address,
        datagram.port,
      );
    });
  }

  test('reset_requestを送り、同じrequest_idの結果を受け取る', () async {
    replyWith(
      (request) => {
        'version': 1,
        'type': 'reset_result',
        'request_id': request['request_id'],
        'status': 'ok',
        'code': 'reset_finished',
        'adapter': 'mock',
        'message': 'Yaw reset finished',
      },
    );
    final client = BridgeClient(port: fakeBridge.port);

    final response = await client.requestYawReset(
      host: '127.0.0.1',
      deviceId: 'device-1',
      pose: 'manual',
      stableMs: 3000,
      confidence: 0,
    );

    expect(response.isOk, isTrue);
    expect(response.adapter, 'mock');
    expect(received.first, containsPair('type', 'reset_request'));
    expect(received.first, containsPair('reset', 'yaw'));
    expect(received.first, containsPair('stable_ms', 3000));
  });

  test('応答がなければBridgeExceptionになる', () async {
    final client = BridgeClient(
      port: fakeBridge.port,
      responseTimeout: const Duration(milliseconds: 300),
    );

    await expectLater(
      client.ping('127.0.0.1'),
      throwsA(isA<BridgeException>()),
    );
  });

  test('不正なIPアドレスは送信しない', () async {
    await expectLater(
      const BridgeClient().ping('not-an-ip'),
      throwsA(isA<BridgeException>()),
    );
  });

  test('request_idはUUID v4形式', () {
    expect(
      newRequestId(),
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-'
          r'[0-9a-f]{12}$',
        ),
      ),
    );
  });
}
