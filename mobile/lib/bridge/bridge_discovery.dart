import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'bridge_client.dart';

class DiscoveredBridge {
  const DiscoveredBridge({
    required this.host,
    required this.name,
    required this.adapter,
  });

  final String host;
  final String name;
  final String adapter;
}

class DiscoveryResult {
  const DiscoveryResult({required this.bridges, required this.networks});

  final List<DiscoveredBridge> bridges;

  /// The /24 networks that were probed, e.g. `10.187.4.0/24`. Shown when
  /// nothing is found so the user can see why.
  final List<String> networks;
}

/// Interface name prefixes for cellular data and VPN links. Probing their
/// neighbours would send packets to the carrier network, never to a Bridge.
const _nonLanInterfacePrefixes = [
  'pdp_ip',
  'rmnet',
  'ccmni',
  'utun',
  'ipsec',
  'tun',
];

/// Finds Bridges on the local network.
///
/// Sends `discover` both as a broadcast and as unicast to every host of the
/// phone's own /24 networks. The unicast sweep is what works on iOS, where
/// broadcast needs a multicast entitlement.
class BridgeDiscovery {
  const BridgeDiscovery({
    this.port = bridgeDefaultPort,
    this.listenDuration = const Duration(milliseconds: 1500),
    this.interfaceLister = _listLanAddresses,
  });

  final int port;
  final Duration listenDuration;

  /// Returns the phone's own LAN IPv4 addresses. Injectable for tests.
  final Future<List<String>> Function() interfaceLister;

  Future<DiscoveryResult> discover() async {
    final requestId = newRequestId();
    final payload = utf8.encode(
      jsonEncode({
        'version': bridgeProtocolVersion,
        'type': 'discover',
        'request_id': requestId,
      }),
    );

    final ownAddresses = await interfaceLister();
    final targets = sweepTargets(ownAddresses);

    final found = <String, DiscoveredBridge>{};
    await Future.wait([
      _probe(payload, requestId, [InternetAddress('255.255.255.255')], found),
      for (var i = 0; i < targets.length; i += _chunkSize)
        _probe(
          payload,
          requestId,
          targets.sublist(i, min(i + _chunkSize, targets.length)),
          found,
        ),
    ]);

    final bridges = found.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return DiscoveryResult(
      bridges: bridges,
      networks: {
        for (final own in ownAddresses)
          '${own.substring(0, own.lastIndexOf('.'))}.0/24',
      }.toList(),
    );
  }

  static const _chunkSize = 16;

  /// Sends `discover` to [targets] from one socket and collects replies.
  ///
  /// A failed send (e.g. no route, unreachable neighbour) makes dart:io close
  /// the whole socket, which would also drop the Bridge's reply. When that
  /// happens the targets are retried one socket each, so an unreachable host
  /// only takes down its own probe.
  Future<void> _probe(
    List<int> payload,
    String requestId,
    List<InternetAddress> targets,
    Map<String, DiscoveredBridge> found,
  ) async {
    RawDatagramSocket socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    } on SocketException {
      return;
    }
    socket.broadcastEnabled = true;
    var died = false;
    final subscription = socket.listen(
      (event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram != null) _collect(datagram, requestId, found);
      },
      onError: (Object _) => died = true,
      onDone: () => died = true,
    );

    try {
      for (final target in targets) {
        if (died) break;
        try {
          socket.send(payload, target, port);
        } on SocketException {
          died = true;
        }
      }
      await Future<void>.delayed(listenDuration);
    } finally {
      await subscription.cancel();
      socket.close();
    }

    if (died && targets.length > 1) {
      await Future.wait([
        for (final target in targets)
          _probe(payload, requestId, [target], found),
      ]);
    }
  }

  void _collect(
    Datagram datagram,
    String requestId,
    Map<String, DiscoveredBridge> found,
  ) {
    try {
      final json = jsonDecode(utf8.decode(datagram.data));
      if (json is! Map<String, Object?> ||
          json['type'] != 'announce' ||
          json['request_id'] != requestId) {
        return;
      }
      final host = datagram.address.address;
      found[host] = DiscoveredBridge(
        host: host,
        name: json['name'] as String? ?? host,
        adapter: json['adapter'] as String? ?? '',
      );
    } on FormatException {
      // Ignore unrelated datagrams.
    }
  }
}

/// Every other host in the /24 network of each own address.
List<InternetAddress> sweepTargets(List<String> ownAddresses) {
  final targets = <String>{};
  for (final own in ownAddresses) {
    final parts = own.split('.');
    if (parts.length != 4) continue;
    final prefix = parts.take(3).join('.');
    for (var host = 1; host <= 254; host++) {
      targets.add('$prefix.$host');
    }
  }
  targets.removeAll(ownAddresses);
  return targets.map(InternetAddress.new).toList();
}

Future<List<String>> _listLanAddresses() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
  );
  return [
    for (final interface in interfaces)
      if (!_nonLanInterfacePrefixes.any(interface.name.startsWith))
        for (final address in interface.addresses)
          if (!address.isLoopback &&
              !address.isLinkLocal &&
              _isPrivate(address.address))
            address.address,
  ];
}

bool _isPrivate(String address) {
  final octets = address.split('.').map(int.tryParse).toList();
  if (octets.length != 4 || octets.contains(null)) return false;
  final a = octets[0]!, b = octets[1]!;
  return a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168);
}
