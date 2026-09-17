import 'package:shared_preferences/shared_preferences.dart';

import 'bridge_client.dart';

class BridgeSettings {
  const BridgeSettings({required this.host, required this.deviceId});

  static const _hostKey = 'bridge_host';
  static const _deviceIdKey = 'device_id';

  /// Empty until the user enters the Bridge IP address.
  final String host;
  final String deviceId;

  static Future<BridgeSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString(_deviceIdKey);
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = newRequestId();
      await prefs.setString(_deviceIdKey, deviceId);
    }
    return BridgeSettings(
      host: prefs.getString(_hostKey) ?? '',
      deviceId: deviceId,
    );
  }

  Future<BridgeSettings> withHost(String host) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hostKey, host);
    return BridgeSettings(host: host, deviceId: deviceId);
  }
}
