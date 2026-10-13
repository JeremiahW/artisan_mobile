import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'spp_helpers.dart';

class FoundDevice {
  const FoundDevice({
    required this.id,
    required this.name,
    this.bonded = false,
  });

  final String id;
  final String name;
  final bool bonded;
}

class SppLink {
  SppLink();

  static const _method = MethodChannel('artisan/spp');
  static const _incoming = EventChannel('artisan/spp_incoming');

  StreamSubscription<dynamic>? _bytesSub;
  bool connected = false;

  Future<List<FoundDevice>> bonded() async {
    if (!Platform.isAndroid) return const [];
    try {
      final raw = await _method.invokeMethod<List<dynamic>>('bonded');
      return _mapDevices(raw);
    } on MissingPluginException {
      return const [];
    }
  }

  Future<List<FoundDevice>> discover({Duration timeout = const Duration(seconds: 12)}) async {
    if (!Platform.isAndroid) {
      throw StateError(sppRequiresAndroidMessage());
    }
    try {
      final raw = await _method.invokeMethod<List<dynamic>>(
        'discover',
        {'timeoutMs': timeout.inMilliseconds},
      );
      final devices = _mapDevices(raw);
      if (devices.isNotEmpty) return devices;
      // Fallback: at least return already-paired devices.
      return await bonded();
    } on MissingPluginException {
      return await bonded();
    } on PlatformException catch (error) {
      final bondedOnly = await bonded();
      if (bondedOnly.isNotEmpty) return bondedOnly;
      throw StateError(error.message ?? '经典蓝牙扫描失败');
    }
  }

  Future<void> connect(
    String address,
    void Function(List<int>) onData, {
    String? pin,
    String? name,
  }) async {
    if (!Platform.isAndroid) {
      throw StateError(classicSppUnsupportedOnIosMessage(name ?? address));
    }
    await disconnect();
    _bytesSub = _incoming.receiveBroadcastStream().listen((event) {
      if (event == null) {
        connected = false;
        return;
      }
      if (event is Uint8List) {
        onData(event);
      } else if (event is List) {
        onData(event.cast<int>());
      }
    });
    final resolvedPin = pin ?? (name == null ? null : pinFromDeviceName(name));
    try {
      await _method.invokeMethod<bool>('connect', {
        'id': address,
        'pin': ?resolvedPin,
      });
    } on PlatformException catch (error) {
      throw StateError(error.message ?? '经典蓝牙串口连接失败');
    }
    connected = true;
  }

  Future<void> write(List<int> data) async {
    if (!connected) return;
    await _method.invokeMethod<bool>('write', Uint8List.fromList(data));
  }

  Future<void> disconnect() async {
    connected = false;
    await _bytesSub?.cancel();
    _bytesSub = null;
    if (!Platform.isAndroid) return;
    try {
      await _method.invokeMethod<bool>('disconnect');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}

List<FoundDevice> _mapDevices(List<dynamic>? raw) {
  if (raw == null) return const [];
  final byId = <String, FoundDevice>{};
  for (final item in raw) {
    if (item is! Map) continue;
    final id = _normalizeMac(item['id']?.toString() ?? '');
    if (id.isEmpty) continue;
    final name = item['name']?.toString().trim() ?? '';
    final bonded = item['bonded']?.toString() == 'true';
    final next = FoundDevice(
      id: id,
      name: name.isEmpty ? id : name,
      bonded: bonded,
    );
    final previous = byId[id];
    byId[id] = previous == null ? next : _mergeDevice(previous, next);
  }
  final out = byId.values.toList();
  out.sort((a, b) {
    int rank(FoundDevice d) {
      final n = d.name.toLowerCase();
      if (n.contains('kaleido')) return 0;
      if (looksLikeClassicSppName(d.name)) return 1;
      return 2;
    }

    final byName = rank(a) - rank(b);
    if (byName != 0) return byName;
    if (a.bonded != b.bonded) return a.bonded ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return out;
}

String _normalizeMac(String raw) {
  final cleaned = raw.trim().toUpperCase().replaceAll('-', ':');
  if (RegExp(r'^([0-9A-F]{2}:){5}[0-9A-F]{2}$').hasMatch(cleaned)) {
    return cleaned;
  }
  final hex = cleaned.replaceAll(RegExp(r'[^0-9A-F]'), '');
  if (hex.length == 12) {
    return List.generate(6, (i) => hex.substring(i * 2, i * 2 + 2)).join(':');
  }
  return cleaned;
}

FoundDevice _mergeDevice(FoundDevice a, FoundDevice b) {
  final preferBName = _nameScore(b.name) > _nameScore(a.name);
  return FoundDevice(
    id: a.id,
    name: preferBName ? b.name : a.name,
    bonded: a.bonded || b.bonded,
  );
}

int _nameScore(String name) {
  if (name.isEmpty) return 0;
  if (RegExp(r'^([0-9A-F]{2}:){5}[0-9A-F]{2}$').hasMatch(name.toUpperCase())) {
    return 1;
  }
  if (looksLikeClassicSppName(name)) return 4;
  return 2;
}
