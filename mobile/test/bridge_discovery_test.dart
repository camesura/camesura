import 'dart:convert';
import 'dart:io';

import 'package:camesura/bridge/bridge_discovery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('自分の/24ネットワークの他ホストを探索対象にする', () {
    final targets = sweepTargets(['192.168.1.20']).map((a) => a.address);

    expect(targets, hasLength(253));
    expect(targets, contains('192.168.1.1'));
    expect(targets, contains('192.168.1.254'));
    expect(targets, isNot(contains('192.168.1.20')));
    expect(targets, isNot(contains('192.168.1.0')));
    expect(targets, isNot(contains('192.168.1.255')));
  });

  test('discoverに応答したBridgeを返す', () async {
    final fakeBridge = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(fakeBridge.close);
    fakeBridge.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = fakeBridge.receive();
      if (datagram == null) return;
      final request =
          jsonDecode(utf8.decode(datagram.data)) as Map<String, Object?>;
      if (request['type'] != 'discover') return;
      fakeBridge.send(
        utf8.encode(
          jsonEncode({
            'version': 1,
            'type': 'announce',
            'request_id': request['request_id'],
            'status': 'ok',
            'code': 'bridge_ready',
            'adapter': 'slimevr',
            'message': 'Bridge is ready',
            'name': 'youkan-mac',
          }),
        ),
        datagram.address,
        datagram.port,
      );
    });

    final discovery = BridgeDiscovery(
      port: fakeBridge.port,
      listenDuration: const Duration(milliseconds: 300),
      interfaceLister: () async => ['127.0.0.2'],
    );
    final result = await discovery.discover();
    final bridges = result.bridges;

    expect(bridges, hasLength(1));
    expect(bridges.single.host, '127.0.0.1');
    expect(bridges.single.name, 'youkan-mac');
    expect(bridges.single.adapter, 'slimevr');
    expect(result.networks, ['127.0.0.0/24']);
  });
}
