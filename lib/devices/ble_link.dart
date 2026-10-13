import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'device_catalog.dart';
import 'spp_helpers.dart';
import 'spp_link.dart';

class BleLink {
  BluetoothDevice? _device;
  StreamSubscription<List<int>>? _notify;
  BluetoothCharacteristic? _write;
  bool connected = false;

  Future<List<FoundDevice>> scan({
    List<String> prefixes = const [],
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final found = <String, FoundDevice>{};
    final sub = FlutterBluePlus.onScanResults.listen((results) {
      for (final result in results) {
        final advertised = result.advertisementData.advName;
        final name = advertised.isNotEmpty ? advertised : result.device.platformName;
        if (looksLikeClassicSppName(name)) {
          continue;
        }
        if (prefixes.isNotEmpty &&
            !prefixes.any((prefix) => name.toLowerCase().contains(prefix.toLowerCase()))) {
          continue;
        }
        final id = result.device.remoteId.str.trim().toUpperCase();
        if (id.isEmpty) continue;
        final previous = found[id];
        final nextName = name.isEmpty ? id : name;
        if (previous == null ||
            (previous.name == id && nextName != id) ||
            (looksLikeClassicSppName(nextName) && !looksLikeClassicSppName(previous.name))) {
          found[id] = FoundDevice(id: id, name: nextName);
        }
      }
    });
    try {
      await FlutterBluePlus.startScan(timeout: timeout);
      await FlutterBluePlus.isScanning.where((value) => !value).first.timeout(
            timeout + const Duration(seconds: 2),
            onTimeout: () => false,
          );
    } finally {
      await sub.cancel();
      await FlutterBluePlus.stopScan();
    }
    return found.values.toList();
  }

  Future<void> connect({
    required String id,
    required List<GattProfile> profiles,
    required void Function(List<int>) onData,
    String? name,
  }) async {
    final label = name ?? '';
    if (looksLikeClassicSppName(label)) {
      throw StateError(classicSppWrongBleMessage(label));
    }
    await disconnect();
    final device = BluetoothDevice.fromId(id);
    await device.connect(timeout: const Duration(seconds: 12));
    _device = device;
    final services = await device.discoverServices();
    final match = _match(services, profiles);
    final notify = match.$1;
    if (notify == null) {
      throw StateError(
        looksLikeClassicSppName(label)
            ? classicSppWrongBleMessage(label)
            : '设备没有 BLE 通知特征。若是 HC-05 等经典串口模块，请改用「经典蓝牙串口 ASCII」（仅 Android）。',
      );
    }
    await notify.setNotifyValue(true);
    _notify = notify.onValueReceived.listen(onData);
    device.cancelWhenDisconnected(_notify!);
    _write = match.$2;
    connected = true;
  }

  (BluetoothCharacteristic?, BluetoothCharacteristic?) _match(
    List<BluetoothService> services,
    List<GattProfile> profiles,
  ) {
    BluetoothCharacteristic? notify;
    BluetoothCharacteristic? write;
    final wanted = profiles.isEmpty
        ? const <GattProfile>[GattProfile(notify: '')]
        : profiles;
    for (final profile in wanted) {
      for (final service in services) {
        final serviceId = service.uuid.str.toLowerCase();
        if (profile.service != null && serviceId != profile.service!.toLowerCase()) {
          continue;
        }
        for (final characteristic in service.characteristics) {
          final id = characteristic.uuid.str.toLowerCase();
          if (profile.notify.isNotEmpty && id == profile.notify.toLowerCase()) {
            notify = characteristic;
          }
          if (profile.write != null && id == profile.write!.toLowerCase()) {
            write = characteristic;
          }
          notify ??= (characteristic.properties.notify || characteristic.properties.indicate)
              ? characteristic
              : null;
          if (profile.write == null &&
              write == null &&
              (characteristic.properties.write || characteristic.properties.writeWithoutResponse)) {
            write = characteristic;
          }
        }
      }
      if (notify != null) break;
    }
    return (notify, write);
  }

  Future<void> write(List<int> data) async {
    final characteristic = _write;
    if (characteristic == null || data.isEmpty) return;
    final withoutResponse = characteristic.properties.writeWithoutResponse &&
        !characteristic.properties.write;
    await characteristic.write(data, withoutResponse: withoutResponse);
  }

  Future<void> disconnect() async {
    connected = false;
    await _notify?.cancel();
    _notify = null;
    _write = null;
    final device = _device;
    _device = null;
    if (device != null) {
      try {
        await device.disconnect();
      } catch (_) {}
    }
  }
}
