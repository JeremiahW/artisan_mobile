import '../devices/device_session.dart';
import '../models/roast_models.dart';

/// Parsed subset of an Artisan `.aset` (QSettings INI) that Flutter can apply.
class AsetConfig {
  AsetConfig({
    required this.presetId,
    required this.device,
    required this.mode,
    required this.interval,
    required this.swapEtBt,
    required this.eventLabels,
    required this.sliderCommands,
    required this.sliderVisibility,
    required this.buttons,
    required this.kp,
    required this.ki,
    required this.kd,
    required this.pidSv,
    required this.svMin,
    required this.svMax,
    required this.etChannel,
    required this.btChannel,
    required this.filt,
    required this.summary,
  });

  final String presetId;
  final DeviceSettings device;
  final String mode;
  final double interval;
  final bool swapEtBt;
  final List<String> eventLabels;
  final List<String> sliderCommands;
  final List<bool> sliderVisibility;
  final List<EventButton> buttons;
  final double kp;
  final double ki;
  final double kd;
  final double pidSv;
  final double svMin;
  final double svMax;
  final String etChannel;
  final String btChannel;
  final List<int> filt;
  final String summary;
}

Map<String, Map<String, String>> parseAsetIni(String text) {
  final sections = <String, Map<String, String>>{};
  String? current;
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) continue;
    if (line.startsWith('[') && line.endsWith(']')) {
      current = line.substring(1, line.length - 1);
      sections.putIfAbsent(current, () => {});
      continue;
    }
    if (current == null) continue;
    final eq = line.indexOf('=');
    if (eq <= 0) continue;
    sections[current]![line.substring(0, eq)] = line.substring(eq + 1);
  }
  return sections;
}

String decodeQtEscapes(String raw) {
  final buffer = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    if (raw[i] == '\\' && i + 1 < raw.length && raw[i + 1] == 'x') {
      var j = i + 2;
      while (j < raw.length && j < i + 6 && RegExp(r'[0-9a-fA-F]').hasMatch(raw[j])) {
        j++;
      }
      final hex = raw.substring(i + 2, j);
      if (hex.isNotEmpty) {
        buffer.writeCharCode(int.parse(hex, radix: 16));
        i = j - 1;
        continue;
      }
    }
    buffer.write(raw[i]);
  }
  return buffer.toString();
}

List<String> splitCsv(String raw) {
  final out = <String>[];
  final buf = StringBuffer();
  var inQuote = false;
  for (var i = 0; i < raw.length; i++) {
    final ch = raw[i];
    if (ch == '"') {
      inQuote = !inQuote;
      continue;
    }
    if (ch == ',' && !inQuote) {
      out.add(buf.toString().trim());
      buf.clear();
      continue;
    }
    buf.write(ch);
  }
  out.add(buf.toString().trim());
  return out;
}

/// Artisan stores event slider values as `percent/10 + 1` (11 → 100, 1 → 0).
double artisanEventValueToPercent(double stored) => ((stored - 1) * 10).clamp(0, 100);

AsetConfig decodeArtisanAset(String text) {
  final sections = parseAsetIni(text);
  String get(String section, String key, [String fallback = '']) =>
      sections[section]?[key] ?? fallback;

  final deviceId = int.tryParse(get('Device', 'id', '18')) ?? 18;
  final etChannel = get('Device', 'arduinoETChannel', '2');
  final btChannel = get('Device', 'arduinoBTChannel', '1');
  final filt = splitCsv(get('Device', 'ArduinoFILT', '0,0,0,0'))
      .map((e) => int.tryParse(e) ?? 0)
      .toList();
  while (filt.length < 4) {
    filt.add(0);
  }

  final mode = get('General', 'Mode', 'C').toUpperCase() == 'F' ? 'F' : 'C';
  final delayMs = double.tryParse(get('General', 'Delay', '1000')) ?? 1000;
  final swapEtBt = get('General', 'swapETBT', 'false').toLowerCase() == 'true';
  final serialHint = get('SerialPort', 'comport', '');
  final looksKaleido = serialHint.toLowerCase().contains('kaleido') ||
      get('General', 'settingspath', '').toLowerCase().contains('kaleido');

  // Device 19 = ArduinoTC4（Kaleido 双系统常用）；138 = 原生 Kaleido。
  final String presetId;
  final String summary;
  if (deviceId == 138) {
    presetId = 'kaleido-spp';
    summary = 'Kaleido 原生串口协议';
  } else if (deviceId == 19 || looksKaleido) {
    presetId = 'kaleido-tc4';
    summary = 'Arduino TC4 双系统（CHAN $etChannel$btChannel，串口 $serialHint）';
  } else if (deviceId == 134) {
    presetId = 'santoker-spp';
    summary = 'Santoker 串口';
  } else {
    presetId = 'kaleido-tc4';
    summary = '按 Kaleido 双系统 TC4 处理（原设备 id=$deviceId）';
  }

  final etypes = splitCsv(decodeQtEscapes(get('events', 'etypes', 'Fan,Drum,Damper,Heater,--')));
  final eventLabels = List<String>.generate(4, (i) {
    if (i < etypes.length && etypes[i].isNotEmpty && etypes[i] != '--') {
      return etypes[i];
    }
    return eventTypeLabels[i];
  });

  final sliderCommands = splitCsv(get('Sliders', 'slidercommands', ',,,,'));
  while (sliderCommands.length < 4) {
    sliderCommands.add('');
  }
  final sliderVisibility = splitCsv(get('Sliders', 'slidervisibilities', '1,1,1,1'))
      .map((e) => e == '1' || e.toLowerCase() == 'true')
      .toList();
  while (sliderVisibility.length < 4) {
    sliderVisibility.add(true);
  }

  final labels = splitCsv(decodeQtEscapes(get('ExtraEventButtons', 'extraeventslabels', '')));
  final actions = splitCsv(get('ExtraEventButtons', 'extraeventsactions', ''));
  final actionStrings = splitCsv(get('ExtraEventButtons', 'extraeventsactionstrings', ''));
  final types = splitCsv(get('ExtraEventButtons', 'extraeventstypes', ''));
  final values = splitCsv(get('ExtraEventButtons', 'extraeventsvalues', ''));
  final visibility = splitCsv(get('ExtraEventButtons', 'extraeventsvisibility', ''));
  final buttons = <EventButton>[];
  final count = [
    labels.length,
    actions.length,
    actionStrings.length,
    types.length,
    values.length,
  ].reduce((a, b) => a < b ? a : b);
  for (var i = 0; i < count; i++) {
    if (i < visibility.length && visibility[i] == '0') continue;
    final label = labels[i];
    if (label.isEmpty) continue;
    final type = int.tryParse(types[i]) ?? 3;
    // 0-3: etypes; 4: -- / control-only; 7/8: relative variants of damper/heater in this profile.
    final mappedType = switch (type) {
      7 => 2,
      8 => 3,
      4 => 3,
      _ => type.clamp(0, 3),
    };
    final stored = double.tryParse(values[i]) ?? 1;
    final action = int.tryParse(actions[i]) ?? 0;
    buttons.add(EventButton(
      label: label,
      type: mappedType,
      value: artisanEventValueToPercent(stored),
      description: actionStrings[i],
      action: action,
      command: actionStrings[i],
      step: (stored - stored.round()).abs() > 0.01 ? ((stored - 1) * 10) : 0,
    ));
  }

  final device = DeviceSettings(
    presetId: presetId,
    swapEtBt: swapEtBt,
    remoteName: looksKaleido ? 'Kaleido_M' : 'TC4',
  );

  // 说明书：滚筒/风门用按钮、火力用按钮；桌面 aset 仍可能打开滑条。
  // 双系统配置统一改为隐藏事件滑条，主界面用 SV + 控制按钮。
  if (presetId == 'kaleido-tc4') {
    for (var i = 0; i < sliderVisibility.length; i++) {
      sliderVisibility[i] = false;
    }
  }

  return AsetConfig(
    presetId: presetId,
    device: device,
    mode: mode,
    interval: (delayMs / 1000).clamp(0.2, 10),
    swapEtBt: swapEtBt,
    eventLabels: eventLabels,
    sliderCommands: sliderCommands.take(4).toList(),
    sliderVisibility: sliderVisibility.take(4).toList(),
    buttons: buttons,
    kp: double.tryParse(get('ArduinoPID', 'pidKp', '15')) ?? 15,
    ki: double.tryParse(get('ArduinoPID', 'pidKi', '0.07')) ?? 0.07,
    kd: double.tryParse(get('ArduinoPID', 'pidKd', '0.06')) ?? 0.06,
    pidSv: double.tryParse(get('ArduinoPID', 'svValue', '180')) ?? 180,
    svMin: double.tryParse(get('ArduinoPID', 'svSliderMin', '50')) ?? 50,
    svMax: double.tryParse(get('ArduinoPID', 'svSliderMax', '230')) ?? 230,
    etChannel: etChannel == 'None' ? '0' : etChannel,
    btChannel: btChannel == 'None' ? '0' : btChannel,
    filt: filt.take(4).toList(),
    summary: summary,
  );
}

bool isTc4Preset(String presetId) =>
    presetId == 'kaleido-tc4' || presetId == 'arduino-tc4';
