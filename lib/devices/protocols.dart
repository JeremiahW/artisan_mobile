import 'dart:math' as math;

import '../models/roast_models.dart';

class Outgoing {
  const Outgoing.bytes(this.bytes) : text = null;
  const Outgoing.text(this.text) : bytes = null;

  final List<int>? bytes;
  final String? text;
}

class PollContext {
  const PollContext({required this.recording, required this.seconds, required this.mode});

  final bool recording;
  final double seconds;
  final String mode;
}

class MachineProtocol {
  Reading reading = const Reading();
  int? _edge;

  int? takeMilestone() {
    final value = _edge;
    _edge = null;
    return value;
  }

  void addBytes(List<int> data) {}

  void addText(String text) {}

  Outgoing? poll(PollContext ctx) => null;

  Outgoing? command(String action, num value) => null;

  void reset() {
    reading = const Reading();
    _edge = null;
  }

  void _rise(int mark, bool now, bool previous) {
    if (now && !previous) _edge = mark;
  }
}

class ManualProtocol extends MachineProtocol {
  void setTemps(double et, double bt) {
    reading = Reading(et: et, bt: bt, note: reading.note);
  }
}

class SimulatorProtocol extends MachineProtocol {
  final Stopwatch _clock = Stopwatch();

  @override
  void reset() {
    super.reset();
    _clock
      ..reset()
      ..start();
  }

  @override
  Outgoing? poll(PollContext ctx) {
    if (!_clock.isRunning) _clock.start();
    final t = _clock.elapsedMilliseconds / 1000.0;
    final m = t / 60.0;
    final et = 168 + 58 * (1 - math.exp(-m / 2.1));
    final bt = 86 + 122 * (1 - math.exp(-m / 4.4)) - 16 * math.exp(-m / 0.32);
    reading = Reading(et: et, bt: bt, power: 70, fan: 40, drum: 80);
    return null;
  }
}

int modbusCrc(List<int> data) {
  var crc = 0xFFFF;
  for (final byte in data) {
    crc ^= byte & 0xFF;
    for (var i = 0; i < 8; i++) {
      if ((crc & 1) != 0) {
        crc = (crc >> 1) ^ 0xA001;
      } else {
        crc >>= 1;
      }
    }
  }
  return crc & 0xFFFF;
}

class Center309Protocol extends MachineProtocol {
  final List<int> _buf = [];

  @override
  void reset() {
    super.reset();
    _buf.clear();
  }

  @override
  Outgoing? poll(PollContext ctx) => const Outgoing.bytes([0x41]);

  @override
  void addBytes(List<int> data) {
    _buf.addAll(data);
    if (_buf.length > 45) {
      _buf.removeRange(0, _buf.length - 45);
    }
    if (_buf.length < 45) return;
    final frame = _buf.sublist(_buf.length - 45);
    _buf.clear();
    if (frame[0] != 0x02) return;
    var t1 = (frame[7] << 8 | frame[8]) / 10.0;
    var t2 = (frame[9] << 8 | frame[10]) / 10.0;
    if (frame[1] == 0) {
      t1 = (t1 - 32) * 5 / 9;
      t2 = (t2 - 32) * 5 / 9;
    }
    reading = Reading(et: t1, bt: t2);
  }
}

class Center302Protocol extends MachineProtocol {
  final List<int> _buf = [];

  @override
  void reset() {
    super.reset();
    _buf.clear();
  }

  @override
  Outgoing? poll(PollContext ctx) => const Outgoing.bytes([0x41]);

  @override
  void addBytes(List<int> data) {
    _buf.addAll(data);
    if (_buf.length < 7) return;
    final frame = _buf.sublist(_buf.length - 7);
    _buf.clear();
    final bits = frame[2];
    final divide = ((bits >> 2) & 1) == 0;
    final digits = (frame[3] << 8 | frame[4]).toRadixString(16).padLeft(4, '0');
    if (!RegExp(r'^\d+$').hasMatch(digits)) return;
    var temp = double.parse(digits);
    if (divide) temp /= 10;
    reading = Reading(et: -1, bt: temp);
  }
}

class ModbusRtuProtocol extends MachineProtocol {
  ModbusRtuProtocol({
    this.slave = 1,
    this.address = 0,
    this.function = 4,
    this.scale = 10,
  });

  int slave;
  int address;
  int function;
  double scale;
  final List<int> _buf = [];

  @override
  void reset() {
    super.reset();
    _buf.clear();
  }

  @override
  Outgoing? poll(PollContext ctx) {
    final body = [
      slave & 0xFF,
      function & 0xFF,
      (address >> 8) & 0xFF,
      address & 0xFF,
      0,
      2,
    ];
    final crc = modbusCrc(body);
    return Outgoing.bytes([...body, crc & 0xFF, (crc >> 8) & 0xFF]);
  }

  @override
  void addBytes(List<int> data) {
    _buf.addAll(data);
    if (_buf.length > 64) _buf.removeRange(0, _buf.length - 64);
    if (_buf.length < 9) return;
    for (var i = 0; i <= _buf.length - 9; i++) {
      if (_buf[i] != (slave & 0xFF) || _buf[i + 1] != (function & 0xFF)) continue;
      if (_buf[i + 2] != 4) continue;
      final frame = _buf.sublist(i, i + 9);
      final crc = modbusCrc(frame.sublist(0, 7));
      if (frame[7] != (crc & 0xFF) || frame[8] != ((crc >> 8) & 0xFF)) continue;
      final rawEt = (frame[3] << 8) | frame[4];
      final rawBt = (frame[5] << 8) | frame[6];
      final div = scale == 0 ? 1 : scale;
      reading = Reading(et: rawEt / div, bt: rawBt / div);
      _buf.removeRange(0, i + 9);
      return;
    }
  }
}

class AsciiProtocol extends MachineProtocol {
  String _line = '';

  @override
  void reset() {
    super.reset();
    _line = '';
  }

  @override
  void addBytes(List<int> data) {
    _line += String.fromCharCodes(data).replaceAll('\r', '\n');
    while (_line.contains('\n')) {
      final cut = _line.indexOf('\n');
      final line = _line.substring(0, cut).trim();
      _line = _line.substring(cut + 1);
      _parse(line);
    }
  }

  @override
  void addText(String text) => addBytes(text.codeUnits);

  void _parse(String line) {
    if (line.isEmpty) return;
    final parts = line.split(RegExp(r'[,\s;]+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return;
    final a = double.tryParse(parts[0]);
    if (a == null) return;
    if (parts.length == 1) {
      reading = Reading(et: -1, bt: a);
      return;
    }
    final b = double.tryParse(parts[1]);
    if (b == null) return;
    reading = Reading(et: a, bt: b);
  }
}

class SantokerProtocol extends MachineProtocol {
  final List<int> _buf = [];
  bool _charge = false;
  bool _dry = false;
  bool _fcs = false;
  bool _scs = false;
  bool _drop = false;
  bool bleHeader = true;

  double _et = -1;
  double _bt = -1;
  int? _power;
  int? _fan;
  int? _drum;

  static const power = 0xFA;
  static const air = 0xCA;
  static const drum = 0xC0;

  @override
  void reset() {
    super.reset();
    _buf.clear();
    _charge = _dry = _fcs = _scs = _drop = false;
    _et = -1;
    _bt = -1;
    _power = _fan = _drum = null;
  }

  @override
  void addBytes(List<int> data) {
    _buf.addAll(data);
    if (_buf.length > 2048) _buf.removeRange(0, _buf.length - 512);
    while (_buf.isNotEmpty) {
      final start = _buf.indexOf(0xEE);
      if (start < 0) {
        _buf.clear();
        return;
      }
      if (start > 0) _buf.removeRange(0, start);
      if (_buf.length < 6) return;
      final marker = _buf[1];
      if (marker != 0xB5 && marker != 0xA5) {
        _buf.removeAt(0);
        continue;
      }
      if (_buf[3] != 0x02 || _buf[4] != 0x04) {
        _buf.removeAt(0);
        continue;
      }
      final len = _buf[5];
      final total = 12 + len;
      if (_buf.length < total) return;
      final frame = _buf.sublist(0, total);
      _buf.removeRange(0, total);
      if (frame[total - 4] != 0xFF ||
          frame[total - 3] != 0xFC ||
          frame[total - 2] != 0xFF ||
          frame[total - 1] != 0xFF) {
        continue;
      }
      bleHeader = marker == 0xB5;
      final payload = frame.sublist(6, 6 + len);
      final crcData = frame.sublist(3, 6 + len);
      final crc = modbusCrc(crcData);
      if (frame[6 + len + 1] != (crc & 0xFF) && frame[6 + len] != ((crc >> 8) & 0xFF)) {
        // Artisan only requires the low CRC byte to match the calculated low byte,
        // and some machines put the CRC in big-endian order.
        final beOk = frame[6 + len] == ((crc >> 8) & 0xFF);
        final leOk = frame[6 + len + 1] == (crc & 0xFF);
        if (!beOk && !leOk) continue;
      }
      _apply(frame[2], payload);
    }
  }

  void _apply(int target, List<int> data) {
    if (data.isEmpty) return;
    int value;
    if (target == 0xF5 || target == 0xF6) {
      if (data.length < 2) return;
      final unsigned = ((data[0] & 0x0F) << 8) | data[1];
      value = (data[0] & 0xF0) == 0xB0 ? unsigned : -unsigned;
    } else {
      value = 0;
      for (final b in data) {
        value = (value << 8) | b;
      }
    }
    if (target == 0xF3 || target == 0xF1) {
      _bt = _smooth(_bt, value / 10);
    } else if (target == 0xF4 || target == 0xF2) {
      _et = _smooth(_et, value / 10);
    } else if (target == 0xFA) {
      _power = value;
    } else if (target == 0xCA) {
      _fan = value;
    } else if (target == 0xC0) {
      _drum = value;
    } else if (target == 0x80) {
      _rise(RoastProfile.charge, value != 0, _charge);
      _charge = value != 0;
    } else if (target == 0x81) {
      _rise(RoastProfile.dry, value != 0, _dry);
      _dry = value != 0;
    } else if (target == 0x82) {
      _rise(RoastProfile.fcs, value != 0, _fcs);
      _fcs = value != 0;
    } else if (target == 0x83) {
      _rise(RoastProfile.scs, value != 0, _scs);
      _scs = value != 0;
    } else if (target == 0x84) {
      _rise(RoastProfile.drop, value != 0, _drop);
      _drop = value != 0;
    }
    reading = Reading(et: _et, bt: _bt, power: _power, fan: _fan, drum: _drum);
  }

  double _smooth(double previous, double next) {
    if (previous <= 0) return next;
    return (2 * next + previous) / 3;
  }

  List<int> frame(int target, int value) {
    final data = [(value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF];
    final body = [0x02, 0x04, 3, ...data];
    final crc = modbusCrc(body);
    final header = bleHeader ? [0xEE, 0xB5] : [0xEE, 0xA5];
    return [
      ...header,
      target & 0xFF,
      ...body,
      (crc >> 8) & 0xFF,
      crc & 0xFF,
      0xFF,
      0xFC,
      0xFF,
      0xFF,
    ];
  }

  @override
  Outgoing? command(String action, num value) {
    switch (action) {
      case 'power':
        return Outgoing.bytes(frame(power, value.round()));
      case 'air':
        return Outgoing.bytes(frame(air, value.round()));
      case 'drum':
        return Outgoing.bytes(frame(drum, value.round()));
      case 'charge':
        return Outgoing.bytes(frame(0x80, 1));
      case 'dry':
        return Outgoing.bytes(frame(0x81, 1));
      case 'fcs':
        return Outgoing.bytes(frame(0x82, 1));
      case 'scs':
        return Outgoing.bytes(frame(0x83, 1));
      case 'drop':
        return Outgoing.bytes(frame(0x84, 1));
    }
    return null;
  }
}

class BlueDotProtocol extends MachineProtocol {
  double _bt = -1;

  @override
  void reset() {
    super.reset();
    _bt = -1;
  }

  @override
  void addBytes(List<int> data) {
    if (data.length <= 4) return;
    final raw = (data[1] & 0xFF) |
        ((data[2] & 0xFF) << 8) |
        ((data[3] & 0xFF) << 16) |
        ((data[4] & 0xFF) << 24);
    var temp = raw.toDouble();
    if (temp > 1000) temp /= 100;
    if (temp.abs() > 400) return;
    _bt = _bt < 0 ? temp : (2 * temp + _bt) / 3;
    reading = Reading(bt: _bt, et: -1);
  }
}

class IkawaProtocol extends MachineProtocol {
  final List<int> _buf = [];
  int _seq = 1;

  @override
  void reset() {
    super.reset();
    _buf.clear();
    _seq = 1;
  }

  @override
  Outgoing? poll(PollContext ctx) {
    final payload = <int>[0x08, 0x0B, 0x10, ..._varint(_seq)];
    _seq = (_seq + 1) % 32767;
    if (_seq == 0) _seq = 1;
    final crc = _crc16(payload, 65535);
    return Outgoing.bytes([0x7E, ..._escape([...payload, ...crc]), 0x7E]);
  }

  @override
  void addBytes(List<int> data) {
    _buf.addAll(data);
    while (true) {
      final start = _buf.indexOf(0x7E);
      if (start < 0) {
        _buf.clear();
        return;
      }
      if (start > 0) _buf.removeRange(0, start);
      final end = _buf.indexOf(0x7E, 1);
      if (end < 0) return;
      final framed = _buf.sublist(1, end);
      _buf.removeRange(0, end + 1);
      if (framed.length < 3) continue;
      final message = _unescape(framed);
      if (message.length < 3) continue;
      final payload = message.sublist(0, message.length - 2);
      final crc = message.sublist(message.length - 2);
      final expect = _crc16(payload, 65535);
      if (crc[0] != expect[0] || crc[1] != expect[1]) continue;
      _decode(payload);
    }
  }

  void _decode(List<int> payload) {
    final top = _readFields(payload);
    final status = top[13];
    if (status is! List<int>) return;
    final fields = _readFields(status);
    int? above = _uint(fields[2]) ?? _uint(fields[22]);
    int? below = _uint(fields[12]) ?? _uint(fields[23]);
    final fan = _uint(fields[3]);
    final heater = _uint(fields[5]);
    final setpoint = _uint(fields[9]);
    reading = Reading(
      et: below == null ? -1 : below / 10,
      bt: above == null ? -1 : above / 10,
      fan: fan == null ? null : (fan / 2.55).round(),
      power: heater == null ? null : heater * 2,
      setpoint: setpoint == null ? null : setpoint / 10,
    );
  }
}

class AcaiaProtocol extends MachineProtocol {
  final List<int> _buf = [];

  @override
  void reset() {
    super.reset();
    _buf.clear();
  }

  @override
  Outgoing? poll(PollContext ctx) {
    if (ctx.seconds.round() % 5 == 0) {
      return Outgoing.bytes(_raw(0, const [0x02, 0x00]));
    }
    return null;
  }

  @override
  Outgoing? command(String action, num value) {
    if (action == 'tare') return Outgoing.bytes(_raw(4, const [0x00]));
    return null;
  }

  List<int> identify() => _raw(11, List<int>.filled(15, 0x2D));

  List<int> fastNotifications() => _raw(12, const [0x03, 0x00, 0x01]);

  List<int> _raw(int type, List<int> payload) {
    return [0xEF, 0xDD, type, ...payload, ..._acaiaCrc(payload)];
  }

  @override
  void addBytes(List<int> data) {
    _buf.addAll(data);
    if (_buf.length > 1024) _buf.removeRange(0, _buf.length - 256);
    while (_buf.length >= 6) {
      final start = _indexOfHeader();
      if (start < 0) {
        _buf.clear();
        return;
      }
      if (start > 0) _buf.removeRange(0, start);
      if (_buf.length < 4) return;
      final cmd = _buf[2];
      final len = _buf[3];
      final total = 4 + (len - 1) + 2;
      if (len < 1 || total > 80) {
        _buf.removeAt(0);
        continue;
      }
      if (_buf.length < total) return;
      final packet = _buf.sublist(0, total);
      _buf.removeRange(0, total);
      final signed = packet.sublist(3, 3 + len);
      final crc = packet.sublist(3 + len, 3 + len + 2);
      final expect = _acaiaCrc(signed);
      if (crc[0] != expect[0] || crc[1] != expect[1]) continue;
      if (cmd == 12) {
        _parseEvents(signed);
      }
    }
  }

  int _indexOfHeader() {
    for (var i = 0; i < _buf.length - 1; i++) {
      if (_buf[i] == 0xEF && _buf[i + 1] == 0xDD) return i;
    }
    return -1;
  }

  void _parseEvents(List<int> data) {
    if (data.length < 3) return;
    final event = data[1];
    if (event != 5 || data.length < 8) return;
    final payload = data.sublist(2);
    var value = (payload[0] & 0xFF) |
        ((payload[1] & 0xFF) << 8) |
        ((payload[2] & 0xFF) << 16) |
        ((payload[3] & 0xFF) << 24);
    final factor = payload[4];
    var weight = value.toDouble();
    if (factor == 1) weight /= 10;
    if (factor == 2) weight /= 100;
    if (factor == 3) weight /= 1000;
    if (factor == 4) weight /= 10000;
    if ((payload[5] & 0x02) != 0) weight = -weight;
    reading = Reading(et: reading.et, bt: reading.bt, weight: weight);
  }
}

/// Arduino / TC4 text protocol used by Kaleido "双系统" Artisan profiles.
///
/// Init: `CHAN;<et><bt>00`, `UNITS;<C|F>`, `FILT;a,b,c,d`
/// Poll: `READ` → `ambient,ET,BT[,heater,fan,SV]`
/// Control: `OT1,<heater>`, `OT2,<damper>`, `IO3,<drum>`, `PID;ON|OFF`, `PID;SV;<n>`
class ArduinoTc4Protocol extends MachineProtocol {
  ArduinoTc4Protocol({
    this.etChannel = '2',
    this.btChannel = '1',
    List<int>? filt,
    this.mode = 'C',
  }) : filt = filt ?? <int>[0, 0, 0, 0];

  String etChannel;
  String btChannel;
  List<int> filt;
  String mode;

  String _pending = '';
  int _step = 0;
  bool _ready = false;
  bool _awaitingAck = false;

  @override
  void reset() {
    super.reset();
    _pending = '';
    _step = 0;
    _ready = false;
    _awaitingAck = false;
  }

  @override
  Outgoing? poll(PollContext ctx) {
    mode = ctx.mode;
    if (_awaitingAck) return null;
    if (!_ready) {
      _awaitingAck = true;
      if (_step == 0) {
        final et = etChannel == 'None' ? '0' : etChannel;
        final bt = btChannel == 'None' ? '0' : btChannel;
        return Outgoing.text('CHAN;$et$bt' '00\n');
      }
      if (_step == 1) {
        return Outgoing.text('UNITS;${mode.toUpperCase()}\n');
      }
      if (_step == 2) {
        final f = List<int>.generate(4, (i) => i < filt.length ? filt[i] : 0);
        return Outgoing.text('FILT;${f.join(",")}\n');
      }
    }
    return const Outgoing.text('READ\n');
  }

  @override
  void addBytes(List<int> data) => addText(String.fromCharCodes(data));

  @override
  void addText(String text) {
    _pending += text.replaceAll('\r', '\n');
    while (_pending.contains('\n')) {
      final cut = _pending.indexOf('\n');
      final line = _pending.substring(0, cut).trim();
      _pending = _pending.substring(cut + 1);
      _consume(line);
    }
  }

  void _consume(String line) {
    if (line.isEmpty) return;
    if (!_ready) {
      if (line.startsWith('#')) {
        _awaitingAck = false;
        _step += 1;
        if (_step >= 3) _ready = true;
      } else if (!line.startsWith('#')) {
        // Some firmwares ack CHAN with empty/#; still advance after any reply.
        _awaitingAck = false;
        if (_step < 3) {
          _step += 1;
          if (_step >= 3) _ready = true;
        }
      }
      if (!_ready) return;
      // Fall through if this line is already a READ payload.
      if (!line.contains(',')) return;
    }

    final parts = line.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (parts.length < 3) return;
    double parseAt(int i) {
      if (i >= parts.length) return -1;
      return double.tryParse(parts[i]) ?? -1;
    }

    final ambient = parseAt(0);
    final et = etChannel == 'None' || etChannel == '0' ? -1.0 : parseAt(1);
    final bt = btChannel == 'None' || btChannel == '0' ? -1.0 : parseAt(2);
    final heater = parts.length > 3 ? parseAt(3).round() : null;
    final fan = parts.length > 4 ? parseAt(4).round() : null;
    final sv = parts.length > 5 ? parseAt(5) : null;
    reading = Reading(
      et: et,
      bt: bt,
      power: heater,
      fan: fan,
      drum: reading.drum,
      setpoint: sv != null && sv > 0 ? sv : reading.setpoint,
      note: ambient > 0 ? 'AT ${ambient.toStringAsFixed(1)}' : reading.note,
    );
  }

  @override
  Outgoing? command(String action, num value) {
    switch (action) {
      case 'power':
      case 'heater':
        return Outgoing.text('OT1,${value.round()}\n');
      case 'air':
      case 'fan':
      case 'damper':
        return Outgoing.text('OT2,${value.round()}\n');
      case 'drum':
        return Outgoing.text('IO3,${value.round()}\n');
      case 'sv':
        return Outgoing.text('PID;SV;${value.toStringAsFixed(0)}\n');
      case 'pidOn':
        return const Outgoing.text('PID;ON\n');
      case 'pidOff':
        return const Outgoing.text('PID;OFF\n');
    }
    return null;
  }

  Outgoing? serial(String command) {
    var cmd = command.trim();
    if (cmd.isEmpty) return null;
    if (!cmd.endsWith('\n')) cmd = '$cmd\n';
    return Outgoing.text(cmd);
  }
}

class KaleidoProtocol extends MachineProtocol {
  final Map<String, String> _state = {};
  String _pending = '';
  bool _ready = false;
  int _step = 0;

  @override
  void reset() {
    super.reset();
    _state.clear();
    _pending = '';
    _ready = false;
    _step = 0;
  }

  @override
  Outgoing? poll(PollContext ctx) {
    if (!_ready) {
      if (_step == 0) return const Outgoing.text('{[PI]}\n');
      if (_step == 1) return Outgoing.text('{[TU ${ctx.mode}]}\n');
      if (_step == 2) return const Outgoing.text('{[SC AR]}\n');
      return null;
    }
    return const Outgoing.text('{[RD A0]}\n');
  }

  @override
  void addText(String text) {
    _pending += text;
    while (_pending.contains('\n')) {
      final cut = _pending.indexOf('\n');
      final line = _pending.substring(0, cut).trim();
      _pending = _pending.substring(cut + 1);
      _consume(line);
    }
    if (_pending.contains('}')) {
      final cut = _pending.indexOf('}');
      _consume(_pending.substring(0, cut + 1));
      _pending = _pending.substring(cut + 1);
    }
  }

  @override
  void addBytes(List<int> data) => addText(String.fromCharCodes(data));

  void _consume(String line) {
    if (line.length < 3 || !line.startsWith('{') || !line.endsWith('}')) return;
    final body = line.substring(1, line.length - 1);
    final parts = body.split(',');
    if (parts.isEmpty) return;
    final sid = int.tryParse(parts.first.trim());
    if (sid != null) {
      _state['sid'] = '$sid';
      if (!_ready) {
        _step = math.min(3, _step + 1);
        if (_step >= 3) _ready = true;
      }
    }
    for (final part in parts.skip(1)) {
      final pair = part.split(':');
      if (pair.length < 2) continue;
      _state[pair[0].trim()] = pair.sublist(1).join(':').trim();
    }
    double? numOf(String key) => double.tryParse(_state[key] ?? '');
    reading = Reading(
      et: numOf('ET') ?? -1,
      bt: numOf('BT') ?? -1,
      power: numOf('HP')?.round(),
      fan: numOf('FC')?.round(),
      drum: numOf('RC')?.round(),
      setpoint: numOf('TS'),
    );
  }

  @override
  Outgoing? command(String action, num value) {
    switch (action) {
      case 'power':
        return Outgoing.text('{[HP ${value.round()}]}\n');
      case 'air':
        return Outgoing.text('{[FC ${value.round()}]}\n');
      case 'drum':
        return Outgoing.text('{[RC ${value.round()}]}\n');
      case 'sv':
        return Outgoing.text('{[TS ${value.toStringAsFixed(0)}]}\n');
      case 'pidOn':
        return const Outgoing.text('{[AH 1]}\n');
      case 'pidOff':
        return const Outgoing.text('{[AH 0]}\n');
    }
    return null;
  }
}

List<int> _varint(int value) {
  final out = <int>[];
  var v = value;
  do {
    var byte = v & 0x7F;
    v >>= 7;
    if (v != 0) byte |= 0x80;
    out.add(byte);
  } while (v != 0);
  return out;
}

List<int> _crc16(List<int> bytes, int seed) {
  var i = seed;
  for (final b in bytes) {
    final i3 = (b & 255) ^ (i & 255);
    final i4 = i3 ^ ((i3 << 4) & 255);
    i = ((((i >> 8) & 255) | ((i4 << 8) & 65535)) ^ (i4 >> 4)) ^ ((i4 << 3) & 65535);
  }
  final v = i & 65535;
  return [(v >> 8) & 0xFF, v & 0xFF];
}

List<int> _escape(List<int> msg) {
  final out = <int>[];
  for (final b in msg) {
    if (b == 0x7D) {
      out.addAll([0x7D, 0x5D]);
    } else if (b == 0x7E) {
      out.addAll([0x7D, 0x5E]);
    } else {
      out.add(b);
    }
  }
  return out;
}

List<int> _unescape(List<int> msg) {
  final out = <int>[];
  for (var i = 0; i < msg.length; i++) {
    if (msg[i] == 0x7D && i + 1 < msg.length) {
      out.add((msg[i + 1] + 32) & 0xFF);
      i++;
    } else {
      out.add(msg[i]);
    }
  }
  return out;
}

Map<int, Object> _readFields(List<int> data) {
  final fields = <int, Object>{};
  var i = 0;
  while (i < data.length) {
    final key = _takeVarint(data, i);
    if (key == null) break;
    i = key.$2;
    final field = key.$1 >> 3;
    final wire = key.$1 & 7;
    if (wire == 0) {
      final value = _takeVarint(data, i);
      if (value == null) break;
      fields[field] = value.$1;
      i = value.$2;
    } else if (wire == 2) {
      final len = _takeVarint(data, i);
      if (len == null) break;
      i = len.$2;
      final end = math.min(data.length, i + len.$1);
      fields[field] = data.sublist(i, end);
      i = end;
    } else if (wire == 5) {
      i += 4;
    } else if (wire == 1) {
      i += 8;
    } else {
      break;
    }
  }
  return fields;
}

(int, int)? _takeVarint(List<int> data, int start) {
  var result = 0;
  var shift = 0;
  var i = start;
  while (i < data.length && shift <= 28) {
    final byte = data[i++];
    result |= (byte & 0x7F) << shift;
    if ((byte & 0x80) == 0) return (result, i);
    shift += 7;
  }
  return null;
}

int? _uint(Object? value) => value is int ? value : null;

List<int> _acaiaCrc(List<int> payload) {
  var a = 0;
  var b = 0;
  for (var i = 0; i < payload.length; i++) {
    if (i.isEven) {
      a = (a + payload[i]) & 0xFF;
    } else {
      b = (b + payload[i]) & 0xFF;
    }
  }
  return [a, b];
}
