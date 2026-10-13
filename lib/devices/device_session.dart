import 'dart:async';
import 'dart:io';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'ble_link.dart';
import 'device_catalog.dart';
import 'protocols.dart';
import 'spp_helpers.dart';
import 'spp_link.dart';
import '../models/roast_models.dart';

class DeviceSettings {
  DeviceSettings({
    this.presetId = 'simulator',
    this.host = '192.168.4.1',
    this.port = 80,
    this.slave = 1,
    this.address = 0,
    this.function = 4,
    this.scale = 10,
    this.remoteId = '',
    this.remoteName = '',
    this.swapEtBt = false,
    this.etChannel = '2',
    this.btChannel = '1',
    List<int>? filt,
  }) : filt = filt ?? <int>[0, 0, 0, 0];

  String presetId;
  String host;
  int port;
  int slave;
  int address;
  int function;
  double scale;
  String remoteId;
  String remoteName;
  bool swapEtBt;
  String etChannel;
  String btChannel;
  List<int> filt;

  Map<String, dynamic> toJson() => {
        'presetId': presetId,
        'host': host,
        'port': port,
        'slave': slave,
        'address': address,
        'function': function,
        'scale': scale,
        'remoteId': remoteId,
        'remoteName': remoteName,
        'swapEtBt': swapEtBt,
        'etChannel': etChannel,
        'btChannel': btChannel,
        'filt': filt,
      };

  factory DeviceSettings.fromJson(Map<String, dynamic> json) => DeviceSettings(
        presetId: json['presetId'] as String? ?? 'simulator',
        host: json['host'] as String? ?? '192.168.4.1',
        port: (json['port'] as num?)?.toInt() ?? 80,
        slave: (json['slave'] as num?)?.toInt() ?? 1,
        address: (json['address'] as num?)?.toInt() ?? 0,
        function: (json['function'] as num?)?.toInt() ?? 4,
        scale: (json['scale'] as num?)?.toDouble() ?? 10,
        remoteId: json['remoteId'] as String? ?? '',
        remoteName: json['remoteName'] as String? ?? '',
        swapEtBt: json['swapEtBt'] as bool? ?? false,
        etChannel: json['etChannel'] as String? ?? '2',
        btChannel: json['btChannel'] as String? ?? '1',
        filt: (json['filt'] as List<dynamic>?)
                ?.map((e) => (e as num).toInt())
                .toList() ??
            <int>[0, 0, 0, 0],
      );
}

class DeviceSession {
  final BleLink ble = BleLink();
  final SppLink spp = SppLink();
  WebSocketChannel? _socket;
  StreamSubscription<dynamic>? _socketSub;
  MachineProtocol protocol = SimulatorProtocol();
  TransportKind transport = TransportKind.none;
  bool swapEtBt = false;
  final List<String> log = [];
  String status = '未连接';

  Reading get reading {
    final raw = protocol.reading;
    if (!swapEtBt) return raw;
    return Reading(
      et: raw.bt,
      bt: raw.et,
      power: raw.power,
      fan: raw.fan,
      drum: raw.drum,
      weight: raw.weight,
      setpoint: raw.setpoint,
      note: raw.note,
    );
  }

  MachineProtocol build(DevicePreset preset, DeviceSettings settings) {
    switch (preset.protocol) {
      case ProtocolKind.simulator:
        return SimulatorProtocol();
      case ProtocolKind.manual:
        return ManualProtocol();
      case ProtocolKind.center309:
        return Center309Protocol();
      case ProtocolKind.center302:
        return Center302Protocol();
      case ProtocolKind.modbusRtu:
        return ModbusRtuProtocol(
          slave: settings.slave,
          address: settings.address,
          function: settings.function,
          scale: settings.scale,
        );
      case ProtocolKind.santoker:
        return SantokerProtocol();
      case ProtocolKind.bluedot:
        return BlueDotProtocol();
      case ProtocolKind.ikawa:
        return IkawaProtocol();
      case ProtocolKind.acaia:
        return AcaiaProtocol();
      case ProtocolKind.ascii:
        return AsciiProtocol();
      case ProtocolKind.kaleido:
        return KaleidoProtocol();
      case ProtocolKind.arduinoTc4:
        return ArduinoTc4Protocol(
          etChannel: settings.etChannel,
          btChannel: settings.btChannel,
          filt: settings.filt,
        );
    }
  }

  Future<void> connect(DevicePreset preset, DeviceSettings settings) async {
    await disconnect();
    protocol = build(preset, settings);
    protocol.reset();
    transport = preset.transport;
    swapEtBt = settings.swapEtBt;
    void onBytes(List<int> data) {
      protocol.addBytes(data);
      _note('收 ${data.length} 字节');
    }

    switch (preset.transport) {
      case TransportKind.none:
        status = preset.name;
        break;
      case TransportKind.ble:
        if (settings.remoteId.isEmpty) {
          throw StateError('还没有选择蓝牙设备');
        }
        if (looksLikeClassicSppName(settings.remoteName)) {
          throw StateError(classicSppWrongBleMessage(settings.remoteName));
        }
        await ble.connect(
          id: settings.remoteId,
          profiles: preset.gatt,
          onData: onBytes,
          name: settings.remoteName,
        );
        status = settings.remoteName.isEmpty ? settings.remoteId : settings.remoteName;
        if (protocol is AcaiaProtocol) {
          final acaia = protocol as AcaiaProtocol;
          await ble.write(acaia.identify());
          await ble.write(acaia.fastNotifications());
        }
        break;
      case TransportKind.spp:
        if (!Platform.isAndroid) {
          throw StateError(
            classicSppUnsupportedOnIosMessage(
              settings.remoteName.isEmpty ? '经典蓝牙串口' : settings.remoteName,
            ),
          );
        }
        if (settings.remoteId.isEmpty) {
          throw StateError('还没有选择蓝牙串口设备');
        }
        await spp.connect(
          settings.remoteId,
          onBytes,
          name: settings.remoteName,
          pin: pinFromDeviceName(settings.remoteName),
        );
        status = settings.remoteName.isEmpty ? settings.remoteId : settings.remoteName;
        break;
      case TransportKind.websocket:
        final uri = Uri.parse('ws://${settings.host}:${settings.port}/ws');
        final socket = WebSocketChannel.connect(uri);
        await socket.ready.timeout(const Duration(seconds: 6));
        _socket = socket;
        _socketSub = socket.stream.listen(
          (event) {
            final text = event is String ? event : String.fromCharCodes((event as List).cast<int>());
            protocol.addText(text);
          },
          onError: (Object error) => status = '连接中断',
          onDone: () => status = '已断开',
        );
        status = uri.toString();
        break;
    }
    _note('已连接 $status');
  }

  void poll(PollContext ctx) {
    final outgoing = protocol.poll(ctx);
    unawaited(_send(outgoing));
  }

  void command(String action, num value) {
    unawaited(_send(protocol.command(action, value)));
  }

  void sendSerial(String command) {
    final protocol = this.protocol;
    if (protocol is ArduinoTc4Protocol) {
      unawaited(_send(protocol.serial(command)));
      return;
    }
    var cmd = command.trim();
    if (cmd.isEmpty) return;
    if (!cmd.endsWith('\n')) cmd = '$cmd\n';
    unawaited(_send(Outgoing.text(cmd)));
  }

  Future<void> _send(Outgoing? outgoing) async {
    if (outgoing == null) return;
    try {
      final bytes = outgoing.bytes;
      final text = outgoing.text;
      if (bytes != null) {
        if (transport == TransportKind.ble) await ble.write(bytes);
        if (transport == TransportKind.spp) await spp.write(bytes);
        _note('发 ${bytes.length} 字节');
      }
      if (text != null) {
        if (transport == TransportKind.websocket) _socket?.sink.add(text);
        if (transport == TransportKind.spp) await spp.write(text.codeUnits);
        _note('发 ${text.trim()}');
      }
    } catch (error) {
      _note('发送失败 $error');
    }
  }

  Future<void> disconnect() async {
    await ble.disconnect();
    await spp.disconnect();
    await _socketSub?.cancel();
    _socketSub = null;
    try {
      await _socket?.sink.close();
    } catch (_) {}
    _socket = null;
    transport = TransportKind.none;
    status = '未连接';
  }

  void _note(String line) {
    log.add(line);
    if (log.length > 40) log.removeAt(0);
  }
}
