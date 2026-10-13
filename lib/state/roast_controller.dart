import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/aset_codec.dart';
import '../core/curve_math.dart';
import '../core/profile_codec.dart';
import '../devices/device_catalog.dart';
import '../devices/device_session.dart';
import '../devices/protocols.dart';
import '../devices/spp_helpers.dart';
import '../devices/spp_link.dart';
import '../models/roast_models.dart';

class RoastController extends ChangeNotifier {
  RoastController();

  final session = DeviceSession();
  final profile = RoastProfile();
  RoastProfile? background;

  DeviceSettings device = DeviceSettings();
  String mode = 'C';
  double interval = 1;
  double rorSpan = 30;
  int smooth = 3;
  double aucBase = 0;
  double targetTemp = 205;
  double dryTemp = 150;
  double fcsTemp = 196;
  bool showEt = true;
  bool showBt = true;
  bool showDeltaEt = true;
  bool showDeltaBt = true;
  bool showBackground = true;
  bool alignBackground = true;
  bool replayEvents = false;
  bool pidOn = false;
  bool followBackground = false;
  bool showSv = true;
  double pidSv = 200;
  double svMin = 50;
  double svMax = 230;
  double kp = 3;
  double ki = 0.05;
  double kd = 8;
  int batch = 1;
  double manualEt = 180;
  double manualBt = 90;
  final sliders = <double>[40, 80, 70, 30];
  List<String> eventLabels = List<String>.from(eventTypeLabels);
  List<String> sliderCommands = <String>['', '', '', ''];
  List<bool> sliderVisibility = <bool>[true, true, true, true];
  final buttons = <EventButton>[
    EventButton(label: '火力 100', type: 2, value: 100),
    EventButton(label: '火力 80', type: 2, value: 80),
    EventButton(label: '火力 60', type: 2, value: 60),
    EventButton(label: '风力 80', type: 0, value: 80),
    EventButton(label: '风力 50', type: 0, value: 50),
    EventButton(label: '滚筒 90', type: 1, value: 90),
  ];
  final alarms = <AlarmRule>[
    AlarmRule(
      id: 'drop-temp',
      enabled: false,
      source: AlarmSource.bt,
      threshold: 200,
      description: '豆温超过 200°C',
    ),
  ];

  bool monitoring = false;
  bool recording = false;
  bool scanning = false;
  String message = '选择设备后按 ON，再按 START 开始记录。';
  String? alarmText;
  double? liveWeight;
  List<FoundDevice> found = [];
  List<String> recent = [];
  String? currentPath;

  final Stopwatch _watch = Stopwatch();
  Timer? _timer;
  double _timeOffset = 0;
  bool _alive = true;
  double _pidIntegral = 0;
  double _pidError = 0;
  DateTime? _pidTick;
  double _lastPowerSent = -1;
  final Set<int> _replayed = {};
  DateTime _lastCommand = DateTime.fromMillisecondsSinceEpoch(0);

  DevicePreset get preset => presetById(device.presetId);

  Reading get live {
    if (preset.protocol == ProtocolKind.manual) {
      return Reading(et: manualEt, bt: manualBt, weight: liveWeight);
    }
    final reading = session.reading;
    return Reading(
      et: reading.et,
      bt: reading.bt,
      power: reading.power,
      fan: reading.fan,
      drum: reading.drum,
      weight: liveWeight ?? reading.weight,
      setpoint: reading.setpoint,
      note: reading.note,
    );
  }

  double get clockSeconds => _timeOffset + _watch.elapsedMilliseconds / 1000.0;

  List<double?> get etRor => rateOfRise(
        profile.samples,
        false,
        spanSeconds: rorSpan,
        smooth: smooth,
      );

  List<double?> get btRor => rateOfRise(
        profile.samples,
        true,
        spanSeconds: rorSpan,
        smooth: smooth,
      );

  RoastStats get stats => computeStats(profile, aucBase: aucBase);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('artisan.settings');
    if (raw == null) return;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    device = DeviceSettings.fromJson(Map<String, dynamic>.from(json['device'] as Map? ?? {}));
    session.swapEtBt = device.swapEtBt;
    mode = json['mode'] as String? ?? mode;
    interval = (json['interval'] as num?)?.toDouble() ?? interval;
    rorSpan = (json['rorSpan'] as num?)?.toDouble() ?? rorSpan;
    smooth = (json['smooth'] as num?)?.toInt() ?? smooth;
    aucBase = (json['aucBase'] as num?)?.toDouble() ?? aucBase;
    targetTemp = (json['targetTemp'] as num?)?.toDouble() ?? targetTemp;
    dryTemp = (json['dryTemp'] as num?)?.toDouble() ?? dryTemp;
    fcsTemp = (json['fcsTemp'] as num?)?.toDouble() ?? fcsTemp;
    showEt = json['showEt'] as bool? ?? showEt;
    showBt = json['showBt'] as bool? ?? showBt;
    showDeltaEt = json['showDeltaEt'] as bool? ?? showDeltaEt;
    showDeltaBt = json['showDeltaBt'] as bool? ?? showDeltaBt;
    showBackground = json['showBackground'] as bool? ?? showBackground;
    alignBackground = json['alignBackground'] as bool? ?? alignBackground;
    replayEvents = json['replayEvents'] as bool? ?? replayEvents;
    pidSv = (json['pidSv'] as num?)?.toDouble() ?? pidSv;
    svMin = (json['svMin'] as num?)?.toDouble() ?? svMin;
    svMax = (json['svMax'] as num?)?.toDouble() ?? svMax;
    followBackground = json['followBackground'] as bool? ?? followBackground;
    showSv = json['showSv'] as bool? ?? showSv;
    kp = (json['kp'] as num?)?.toDouble() ?? kp;
    ki = (json['ki'] as num?)?.toDouble() ?? ki;
    kd = (json['kd'] as num?)?.toDouble() ?? kd;
    batch = (json['batch'] as num?)?.toInt() ?? batch;
    manualEt = (json['manualEt'] as num?)?.toDouble() ?? manualEt;
    manualBt = (json['manualBt'] as num?)?.toDouble() ?? manualBt;
    final storedSliders = json['sliders'] as List<dynamic>?;
    if (storedSliders != null && storedSliders.length == 4) {
      for (var i = 0; i < 4; i++) {
        sliders[i] = (storedSliders[i] as num).toDouble();
      }
    }
    final storedButtons = json['buttons'] as List<dynamic>?;
    if (storedButtons != null && storedButtons.isNotEmpty) {
      buttons
        ..clear()
        ..addAll(storedButtons.map((e) => EventButton.fromJson(Map<String, dynamic>.from(e as Map))));
    }
    final storedAlarms = json['alarms'] as List<dynamic>?;
    if (storedAlarms != null) {
      alarms
        ..clear()
        ..addAll(storedAlarms.map((e) => AlarmRule.fromJson(Map<String, dynamic>.from(e as Map))));
    }
    recent = (json['recent'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
    final storedLabels = json['eventLabels'] as List<dynamic>?;
    if (storedLabels != null && storedLabels.length >= 4) {
      eventLabels = storedLabels.take(4).map((e) => e.toString()).toList();
    }
    final storedCommands = json['sliderCommands'] as List<dynamic>?;
    if (storedCommands != null && storedCommands.length >= 4) {
      sliderCommands = storedCommands.take(4).map((e) => e.toString()).toList();
    }
    final storedVisibility = json['sliderVisibility'] as List<dynamic>?;
    if (storedVisibility != null && storedVisibility.length >= 4) {
      sliderVisibility = storedVisibility.take(4).map((e) => e == true || e == 1 || e == '1').toList();
    }
    if (_alive) notifyListeners();
  }

  Future<void> persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('artisan.settings', jsonEncode({
      'device': device.toJson(),
      'mode': mode,
      'interval': interval,
      'rorSpan': rorSpan,
      'smooth': smooth,
      'aucBase': aucBase,
      'targetTemp': targetTemp,
      'dryTemp': dryTemp,
      'fcsTemp': fcsTemp,
      'showEt': showEt,
      'showBt': showBt,
      'showDeltaEt': showDeltaEt,
      'showDeltaBt': showDeltaBt,
      'showBackground': showBackground,
      'alignBackground': alignBackground,
      'replayEvents': replayEvents,
      'pidSv': pidSv,
      'svMin': svMin,
      'svMax': svMax,
      'followBackground': followBackground,
      'showSv': showSv,
      'kp': kp,
      'ki': ki,
      'kd': kd,
      'batch': batch,
      'manualEt': manualEt,
      'manualBt': manualBt,
      'sliders': sliders,
      'eventLabels': eventLabels,
      'sliderCommands': sliderCommands,
      'sliderVisibility': sliderVisibility,
      'buttons': buttons.map((e) => e.toJson()).toList(),
      'alarms': alarms.map((e) => e.toJson()).toList(),
      'recent': recent,
    }));
  }

  Future<void> togglePower() async {
    if (monitoring) {
      await powerOff();
      return;
    }
    try {
      if (preset.transport != TransportKind.none) {
        await _ensureRadioPermission();
      }
      await session.connect(preset, device);
      if (session.protocol is ManualProtocol) {
        (session.protocol as ManualProtocol).setTemps(manualEt, manualBt);
      }
      monitoring = true;
      _timer?.cancel();
      _timer = Timer.periodic(
        Duration(milliseconds: (interval * 1000).round().clamp(200, 10000)),
        (_) => _tick(),
      );
      message = '已连接 ${session.status}';
    } catch (error) {
      message = '连接失败：$error';
      await session.disconnect();
    }
    notifyListeners();
  }

  Future<void> powerOff() async {
    recording = false;
    monitoring = false;
    _watch.stop();
    _timer?.cancel();
    await session.disconnect();
    message = '已断开';
    notifyListeners();
  }

  void toggleRecord() {
    if (!monitoring) {
      message = '请先按 ON 连接设备';
      notifyListeners();
      return;
    }
    if (recording) {
      recording = false;
      _watch.stop();
      message = '记录已停止';
      unawaited(autosave());
    } else {
      recording = true;
      _timeOffset = profile.samples.isEmpty ? 0 : profile.samples.last.t;
      _watch
        ..reset()
        ..start();
      for (final alarm in alarms) {
        alarm.fired = false;
      }
      _replayed.clear();
      _pidIntegral = 0;
      _lastPowerSent = -1;
      message = '正在记录';
    }
    notifyListeners();
  }

  void resetCurve() {
    recording = false;
    _watch.stop();
    _timeOffset = 0;
    profile.clearCurve();
    alarmText = null;
    _replayed.clear();
    message = '曲线已清空';
    notifyListeners();
  }

  void mark(int which) {
    if (!recording || profile.samples.isEmpty) {
      message = '开始记录后才能标记阶段';
      notifyListeners();
      return;
    }
    if (profile.timeindex[which] >= 0) {
      for (var i = which; i < profile.timeindex.length; i++) {
        profile.timeindex[i] = -1;
      }
      if (which == RoastProfile.charge) profile.tpIndex = -1;
      message = '已取消${_markName(which)}';
    } else {
      profile.timeindex[which] = profile.samples.length - 1;
      _emitMilestone(which);
      message = '已标记${_markName(which)}';
      if (which == RoastProfile.drop) {
        batch += 1;
        unawaited(autosave());
      }
    }
    notifyListeners();
    unawaited(persist());
  }

  void pressButton(EventButton button) {
    final index = button.type.clamp(0, 3);
    final cmd = button.command.trim();
    final upper = cmd.toUpperCase();

    if (button.action == 20 || upper == 'PIDON' || upper == 'PIDOFF') {
      if (upper.contains('OFF')) {
        pidOn = false;
        followBackground = false;
        session.command('pidOff', 0);
        message = '停止热机 / PID OFF';
      } else {
        // 说明书自动烘焙：开始热机时 SV 取背景曲线入豆温度。
        final bgCharge = background?.sampleAt(RoastProfile.charge);
        if (bgCharge != null && bgCharge.btOk) {
          pidSv = bgCharge.bt.clamp(svMin, svMax);
          followBackground = true;
          replayEvents = true;
          message = '开始热机：SV=${pidSv.toStringAsFixed(0)}（背景入豆温），已开启曲线跟随';
        } else {
          followBackground = false;
          message = '开始热机：SV=${pidSv.toStringAsFixed(0)}';
        }
        pidOn = true;
        session.command('pidOn', 0);
        session.command('sv', pidSv);
      }
    } else if (button.action == 1 || cmd.contains(',') || cmd.startsWith('PID') || cmd.startsWith('HPM') || cmd.startsWith('CLDN')) {
      var value = button.value;
      if (button.step != 0) {
        sliders[index] = (sliders[index] + button.step).clamp(0, 100);
        value = sliders[index];
      } else if (!cmd.contains('UP') && !cmd.contains('DOWN') && !cmd.contains('HPM') && !cmd.startsWith('PID')) {
        sliders[index] = value.clamp(0, 100);
      }
      final filled = cmd
          .replaceAll('{}', '${value.round()}')
          .replaceAll('{0}', '${value.round()}');
      if (filled.toUpperCase().contains('UP') || filled.toUpperCase().contains('DOWN')) {
        final delta = filled.toUpperCase().contains('UP') ? 5.0 : -5.0;
        sliders[index] = (sliders[index] + delta).clamp(0, 100);
        final absolute = filled
            .replaceAll(RegExp(r',UP', caseSensitive: false), ',${sliders[index].round()}')
            .replaceAll(RegExp(r',DOWN', caseSensitive: false), ',${sliders[index].round()}');
        session.sendSerial(absolute);
      } else {
        session.sendSerial(filled);
      }
      message = '已发送 ${button.label}';
    } else {
      sliders[index] = button.value.clamp(0, 100);
      _sendSlider(index, force: true);
    }

    if (recording && profile.samples.isNotEmpty) {
      profile.events.add(RoastEvent(
        t: profile.samples.last.t,
        type: button.type,
        value: sliders[index],
        description: button.description.isEmpty ? button.label : button.description,
      ));
    }
    notifyListeners();
  }

  void setSlider(int index, double value, {bool commit = false}) {
    sliders[index] = value.clamp(0, 100);
    _sendSlider(index, force: commit);
    if (commit && recording && profile.samples.isNotEmpty) {
      final previous = profile.events.where((e) => e.type == index).toList();
      final last = previous.isEmpty ? null : previous.last.value;
      if (last == null || (last - sliders[index]).abs() >= 5) {
        profile.events.add(RoastEvent(
          t: profile.samples.last.t,
          type: index,
          value: sliders[index],
          description: eventLabels[index],
        ));
      }
    }
    notifyListeners();
  }

  void setManual(double? et, double? bt) {
    if (et != null) manualEt = et;
    if (bt != null) manualBt = bt;
    final protocol = session.protocol;
    if (protocol is ManualProtocol) protocol.setTemps(manualEt, manualBt);
    notifyListeners();
  }

  Future<void> scan() async {
    scanning = true;
    found = [];
    notifyListeners();
    try {
      await _ensureRadioPermission(classic: preset.transport == TransportKind.spp);
      if (preset.transport == TransportKind.ble) {
        found = await session.ble.scan(prefixes: preset.prefixes);
      } else if (preset.transport == TransportKind.spp) {
        if (!Platform.isAndroid) {
          throw StateError(sppRequiresAndroidMessage());
        }
        found = await session.spp.discover(timeout: const Duration(seconds: 12));
        final artisan = found.where((d) => looksLikeClassicSppName(d.name)).toList();
        if (found.isEmpty) {
          message = '没有扫到经典蓝牙设备。请确认：'
              '1) 已选蓝牙串口设备而不是 BLE；'
              '2) 系统蓝牙已开；3) 位置权限与定位服务已开；'
              '4) 模块上电/进入配对模式；5) 已在系统蓝牙里配对过则应出现在列表。';
        } else {
          message = '发现 ${found.length} 个设备'
              '${artisan.isEmpty ? '' : '，其中 ${artisan.length} 个像经典 SPP 模块'}';
        }
      } else {
        message = '当前设备不用扫描';
      }
      if (preset.transport != TransportKind.spp) {
        message = found.isEmpty ? '没有发现匹配的设备' : '发现 ${found.length} 个设备';
      }
    } catch (error) {
      message = '扫描失败：$error';
    } finally {
      scanning = false;
      notifyListeners();
    }
  }

  void chooseDevice(FoundDevice item) {
    if (looksLikeClassicSppName(item.name) && preset.transport == TransportKind.ble) {
      device.presetId = 'spp-ascii';
      message = '已自动切换到「经典蓝牙串口 ASCII」。${classicSppWrongBleMessage(item.name)}';
    } else {
      message = '已选择 ${item.name}';
    }
    device.remoteId = item.id;
    device.remoteName = item.name;
    notifyListeners();
    unawaited(persist());
  }

  void setManualAddress(String address, {String? name}) {
    final mac = address.trim().toUpperCase();
    if (!RegExp(r'^([0-9A-F]{2}:){5}[0-9A-F]{2}$').hasMatch(mac)) {
      message = 'MAC 地址格式应为 AA:BB:CC:DD:EE:FF';
      notifyListeners();
      return;
    }
    if (preset.transport != TransportKind.spp) {
      device.presetId = 'spp-ascii';
    }
    device.remoteId = mac;
    device.remoteName = (name == null || name.trim().isEmpty) ? 'SPP' : name.trim();
    message = '已手动设置 ${device.remoteName} ($mac)';
    notifyListeners();
    unawaited(persist());
  }

  bool get canSwapEtBt {
    final kind = preset.protocol;
    return kind == ProtocolKind.ascii ||
        kind == ProtocolKind.center309 ||
        kind == ProtocolKind.center302 ||
        kind == ProtocolKind.modbusRtu ||
        kind == ProtocolKind.santoker ||
        kind == ProtocolKind.kaleido ||
        kind == ProtocolKind.arduinoTc4;
  }

  Future<void> loadBundledKaleidoAset() async {
    final raw = await rootBundle.loadString('assets/settings/Kaleido_双系统.aset');
    applyAset(decodeArtisanAset(raw));
  }

  Future<void> importAsetFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['aset'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    final text = bytes != null
        ? utf8.decode(bytes)
        : (file.path == null ? null : await File(file.path!).readAsString());
    if (text == null || text.isEmpty) {
      message = '无法读取 .aset 文件';
      notifyListeners();
      return;
    }
    applyAset(decodeArtisanAset(text));
  }

  void applyAset(AsetConfig config) {
    final keepRemoteId = device.remoteId;
    final keepRemoteName = device.remoteName;
    device = config.device;
    if (keepRemoteId.isNotEmpty) {
      device.remoteId = keepRemoteId;
      if (keepRemoteName.isNotEmpty) device.remoteName = keepRemoteName;
    }
    device.etChannel = config.etChannel;
    device.btChannel = config.btChannel;
    device.filt = List<int>.from(config.filt);
    mode = config.mode;
    interval = config.interval;
    swapEtBtViaSettings(config.swapEtBt);
    eventLabels = List<String>.from(config.eventLabels);
    sliderCommands = List<String>.from(config.sliderCommands);
    sliderVisibility = List<bool>.from(config.sliderVisibility);
    buttons
      ..clear()
      ..addAll(config.buttons);
    kp = config.kp;
    ki = config.ki;
    kd = config.kd;
    pidSv = config.pidSv;
    svMin = config.svMin;
    svMax = config.svMax;
    showSv = true;
    message = '已加载配置：${config.summary}。'
        '请用系统蓝牙配对 Kaleido_M（双系统需在触摸屏点允许），再在设备里扫描连接后按 ON。';
    notifyListeners();
    unawaited(persist());
  }

  void setPidSv(double value, {bool send = true}) {
    pidSv = value.clamp(svMin, svMax);
    if (send && monitoring) {
      session.command('sv', pidSv);
    }
    notifyListeners();
    unawaited(persist());
  }

  void nudgePidSv(double delta) => setPidSv(pidSv + delta);

  void swapEtBtViaSettings(bool value) {
    device.swapEtBt = value;
    session.swapEtBt = value;
  }

  void setSwapEtBt(bool value) {
    device.swapEtBt = value;
    session.swapEtBt = value;
    message = value ? '已交换 ET / BT 通道' : '已恢复默认 ET / BT 通道';
    notifyListeners();
    unawaited(persist());
  }

  void selectPreset(String id) {
    device.presetId = id;
    device.remoteId = '';
    device.remoteName = '';
    found = [];
    notifyListeners();
    unawaited(persist());
  }

  Future<void> openProfile({bool backgroundOnly = false}) async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) return;
    final text = utf8.decode(bytes, allowMalformed: true);
    final loaded = decodeProfileText(text);
    if (backgroundOnly) {
      background = loaded;
      _replayed.clear();
      message = '已载入背景 ${loaded.title}';
    } else {
      _replaceProfile(loaded);
      currentPath = file.path;
      message = '已打开 ${loaded.title}';
      if (file.path != null) _remember(file.path!);
    }
    notifyListeners();
  }

  Future<void> openRecent(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      message = '文件不存在';
      notifyListeners();
      return;
    }
    final loaded = decodeProfileText(await file.readAsString());
    _replaceProfile(loaded);
    currentPath = path;
    message = '已打开 ${loaded.title}';
    notifyListeners();
  }

  Future<void> saveProfile() async {
    final directory = await _profileDirectory();
    final safe = profile.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final stamp = profile.roastDate;
    final name =
        '${stamp.year}${stamp.month.toString().padLeft(2, '0')}${stamp.day.toString().padLeft(2, '0')}_'
        '${stamp.hour.toString().padLeft(2, '0')}${stamp.minute.toString().padLeft(2, '0')}_$safe.artisan.json';
    final file = File('${directory.path}/$name');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(profile.toJson()));
    currentPath = file.path;
    _remember(file.path);
    message = '已保存 ${file.path}';
    notifyListeners();
    await persist();
  }

  Future<void> autosave() => saveProfile();

  Future<void> exportCsv() async {
    final csv = encodeArtisanCsv(profile);
    final name = '${profile.title}.csv';
    final path = await FilePicker.platform.saveFile(
      dialogTitle: '导出 CSV',
      fileName: name,
      bytes: utf8.encode(csv),
    );
    message = path == null ? '已取消导出' : '已导出 $path';
    notifyListeners();
  }

  void useAsBackground() {
    background = RoastProfile.fromJson(profile.toJson());
    message = '当前曲线已设为背景';
    notifyListeners();
  }

  void clearBackground() {
    background = null;
    notifyListeners();
  }

  void applyDesigner(List<Sample> curve) {
    background = RoastProfile(title: '设计曲线', samples: curve, timeindex: [0, -1, -1, -1, -1, -1, curve.length - 1, -1]);
    message = '设计曲线已放到背景';
    notifyListeners();
  }

  void captureWeight(bool incoming) {
    final weight = live.weight;
    if (weight == null) {
      message = '还没有秤的读数';
      notifyListeners();
      return;
    }
    if (incoming) {
      profile.weightIn = weight;
    } else {
      profile.weightOut = weight;
    }
    message = incoming ? '入豆重 ${weight.toStringAsFixed(1)} g' : '出豆重 ${weight.toStringAsFixed(1)} g';
    notifyListeners();
  }

  void tareScale() => session.command('tare', 0);

  void dismissAlarm() {
    alarmText = null;
    notifyListeners();
  }

  void changed() {
    notifyListeners();
    unawaited(persist());
  }

  void _tick() {
    if (!_alive || !monitoring) return;
    session.poll(PollContext(recording: recording, seconds: clockSeconds, mode: mode));
    final reading = session.reading;
    if (reading.weight != null) liveWeight = reading.weight;
    _syncSliderFromReading(reading);
    if (!recording) {
      notifyListeners();
      return;
    }
    _updateBackgroundFollow();
    final sample = Sample(
      t: clockSeconds,
      et: reading.et,
      bt: reading.bt,
      sv: pidSv,
      power: reading.power?.toDouble() ?? _heaterSlider(),
      fan: reading.fan?.toDouble(),
      drum: reading.drum?.toDouble() ?? _drumSlider(),
    );
    if (preset.protocol == ProtocolKind.manual) {
      profile.samples.add(Sample(t: clockSeconds, et: manualEt, bt: manualBt, sv: pidSv));
    } else if (sample.etOk || sample.btOk) {
      profile.samples.add(sample);
    } else {
      notifyListeners();
      return;
    }
    final milestone = session.protocol.takeMilestone();
    if (milestone != null &&
        milestone >= 0 &&
        milestone < profile.timeindex.length &&
        profile.timeindex[milestone] < 0) {
      profile.timeindex[milestone] = profile.samples.length - 1;
    }
    final charge = profile.indexOf(RoastProfile.charge);
    if (charge >= 0 && profile.tpIndex < 0) {
      profile.tpIndex = detectTurningPoint(profile.samples, charge) ?? -1;
    }
    _replay();
    _alarms();
    _pid();
    notifyListeners();
  }

  void _replay() {
    final bg = background;
    if (!replayEvents || bg == null || profile.samples.isEmpty) return;
    final fgCharge = profile.sampleAt(RoastProfile.charge);
    if (fgCharge == null) return;
    final bgCharge = bg.sampleAt(RoastProfile.charge);
    final roastTime = profile.samples.last.t - fgCharge.t;
    for (var i = 0; i < bg.events.length; i++) {
      if (_replayed.contains(i)) continue;
      final event = bg.events[i];
      final when = bgCharge == null ? event.t : event.t - bgCharge.t;
      if (roastTime + 0.05 < when) continue;
      _replayed.add(i);
      if (event.type >= 0 && event.type < 4) {
        sliders[event.type] = event.value.clamp(0, 100);
        _sendSlider(event.type, force: true);
      }
      profile.events.add(RoastEvent(
        t: profile.samples.last.t,
        type: event.type,
        value: event.value,
        description: '重放 ${event.description}',
      ));
    }
  }

  void _alarms() {
    if (profile.samples.isEmpty) return;
    final charge = profile.sampleAt(RoastProfile.charge);
    final elapsed = charge == null ? profile.samples.last.t : profile.samples.last.t - charge.t;
    final et = etRor.isEmpty ? null : etRor.last;
    final bt = btRor.isEmpty ? null : btRor.last;
    for (final alarm in alarms) {
      if (!alarm.enabled || alarm.fired) continue;
      if (elapsed < alarm.guardSeconds) continue;
      final value = switch (alarm.source) {
        AlarmSource.time => elapsed,
        AlarmSource.et => live.et,
        AlarmSource.bt => live.bt,
        AlarmSource.deltaEt => et,
        AlarmSource.deltaBt => bt,
      };
      if (value == null) continue;
      if ((alarm.source == AlarmSource.et || alarm.source == AlarmSource.bt) && value <= 0) {
        continue;
      }
      final hit = alarm.compare == AlarmCompare.above ? value >= alarm.threshold : value <= alarm.threshold;
      if (!hit) continue;
      alarm.fired = true;
      alarmText = alarm.description.isEmpty ? '报警' : alarm.description;
      message = alarmText!;
      SystemSound.play(SystemSoundType.alert);
      if (alarm.action == AlarmAction.setSlider) {
        final index = alarm.slider.clamp(0, 3);
        sliders[index] = alarm.actionValue.clamp(0, 100);
        _sendSlider(index, force: true);
      }
    }
  }

  void _updateBackgroundFollow() {
    if (!followBackground || !pidOn) return;
    final bg = background;
    if (bg == null || bg.samples.isEmpty) return;
    final fgCharge = profile.sampleAt(RoastProfile.charge);
    // 热机阶段：保持背景入豆温作 SV；入豆后按背景豆温曲线跟随。
    if (fgCharge == null) {
      final charge = bg.sampleAt(RoastProfile.charge);
      if (charge != null && charge.btOk) {
        final next = charge.bt.clamp(svMin, svMax);
        if ((next - pidSv).abs() >= 0.5) {
          pidSv = next;
          session.command('sv', pidSv);
        }
      }
      return;
    }
    final roastTime = clockSeconds - fgCharge.t;
    final bgCharge = bg.sampleAt(RoastProfile.charge);
    final targetT = bgCharge == null ? roastTime : bgCharge.t + roastTime;
    Sample? nearest;
    for (final sample in bg.samples) {
      if (!sample.btOk) continue;
      if (nearest == null || (sample.t - targetT).abs() < (nearest.t - targetT).abs()) {
        nearest = sample;
      }
      if (sample.t >= targetT) break;
    }
    if (nearest == null) return;
    final next = nearest.bt.clamp(svMin, svMax);
    if ((next - pidSv).abs() >= 0.5) {
      pidSv = next;
      session.command('sv', pidSv);
    }
  }

  void _pid() {
    if (!pidOn || live.bt <= 0) return;
    // Kaleido 双系统：机器端 PID（PIDon + SV）。软件 PID 仅在无 TC4 时兜底调火力。
    if (preset.protocol == ProtocolKind.arduinoTc4 || preset.protocol == ProtocolKind.kaleido) {
      return;
    }
    final now = DateTime.now();
    final dt = _pidTick == null ? interval : now.difference(_pidTick!).inMilliseconds / 1000.0;
    _pidTick = now;
    if (dt <= 0) return;
    final error = pidSv - live.bt;
    _pidIntegral = (_pidIntegral + error * dt).clamp(-80, 80);
    final derivative = (error - _pidError) / dt;
    _pidError = error;
    final output = (kp * error + ki * _pidIntegral + kd * derivative).clamp(0, 100).toDouble();
    final heater = _heaterIndex();
    sliders[heater] = output;
    if ((_lastPowerSent - output).abs() >= 1) {
      _lastPowerSent = output;
      session.command('power', output.round());
      session.command('sv', pidSv);
    }
  }

  int _heaterIndex() {
    for (var i = 0; i < sliderCommands.length; i++) {
      if (sliderCommands[i].toUpperCase().contains('OT1')) return i;
    }
    return 2;
  }

  int _drumIndex() {
    for (var i = 0; i < sliderCommands.length; i++) {
      if (sliderCommands[i].toUpperCase().contains('IO3')) return i;
    }
    return 1;
  }

  double? _heaterSlider() {
    final i = _heaterIndex();
    return i < sliders.length ? sliders[i] : null;
  }

  double? _drumSlider() {
    final i = _drumIndex();
    return i < sliders.length ? sliders[i] : null;
  }

  void _emitMilestone(int which) {
    // .aset DefaultButtons: EVT,1/3/4/5/6/7/8/9 → Kaleido 触摸屏同步事件。
    const evt = [1, 3, 4, 5, 6, 7, 8, 9];
    if (which >= 0 && which < evt.length) {
      session.sendSerial('EVT,${evt[which]}');
    }
    // 说明书：排豆自动开冷却；冷却结束关冷却。
    if (which == RoastProfile.drop) {
      session.sendSerial('CLDN,ON');
    } else if (which == RoastProfile.cool) {
      session.sendSerial('CLDN,OFF');
    }
    session.command(_markCommand(which), 1);
  }

  void _syncSliderFromReading(Reading reading) {
    int? indexFor(String token) {
      for (var i = 0; i < sliderCommands.length && i < 4; i++) {
        if (sliderCommands[i].toUpperCase().contains(token)) return i;
      }
      return null;
    }

    if (reading.power != null && !pidOn) {
      final i = indexFor('OT1') ?? 2;
      sliders[i] = reading.power!.clamp(0, 100).toDouble();
    }
    if (reading.fan != null) {
      final i = indexFor('OT2') ?? 0;
      sliders[i] = reading.fan!.clamp(0, 100).toDouble();
    }
    if (reading.drum != null) {
      final i = indexFor('IO3') ?? 1;
      sliders[i] = reading.drum!.clamp(0, 100).toDouble();
    }
    if (reading.setpoint != null && reading.setpoint! > 0) {
      pidSv = reading.setpoint!;
    }
  }

  void _sendSlider(int index, {required bool force}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastCommand).inMilliseconds < 250) return;
    _lastCommand = now;
    if (index < 0 || index > 3) return;
    final template = index < sliderCommands.length ? sliderCommands[index].trim() : '';
    if (template.isNotEmpty) {
      final filled = template.replaceAll('{}', '${sliders[index].round()}');
      session.sendSerial(filled);
      return;
    }
    // Default Artisan-like mapping for TC4 / Kaleido 双系统:
    // 0 airflow→OT2, 1 drum→IO3, 2 power→OT1, 3 damper→OT2
    const actions = ['air', 'drum', 'power', 'damper'];
    session.command(actions[index], sliders[index].round());
  }

  void _replaceProfile(RoastProfile loaded) {
    recording = false;
    _watch.stop();
    profile.clearCurve();
    profile
      ..title = loaded.title
      ..beans = loaded.beans
      ..operatorName = loaded.operatorName
      ..machine = loaded.machine
      ..notes = loaded.notes
      ..weightIn = loaded.weightIn
      ..weightOut = loaded.weightOut
      ..moisture = loaded.moisture
      ..color = loaded.color
      ..mode = loaded.mode
      ..roastDate = loaded.roastDate
      ..cuppingNotes = loaded.cuppingNotes
      ..tpIndex = loaded.tpIndex;
    profile.samples.addAll(loaded.samples);
    profile.events.addAll(loaded.events);
    for (var i = 0; i < 8; i++) {
      profile.timeindex[i] = loaded.timeindex[i];
    }
    for (var i = 0; i < 10; i++) {
      profile.flavors[i] = loaded.flavors[i];
    }
    mode = profile.mode;
  }

  Future<Directory> _profileDirectory() async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory('${root.path}/profiles');
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  void _remember(String path) {
    recent.remove(path);
    recent.insert(0, path);
    if (recent.length > 12) recent.removeRange(12, recent.length);
    unawaited(persist());
  }

  Future<void> _ensureRadioPermission({bool classic = false}) async {
    if (kIsWeb || !Platform.isAndroid) return;
    final scan = await Permission.bluetoothScan.request();
    final connect = await Permission.bluetoothConnect.request();
    // Classic discovery on Vivo/Xiaomi/etc. usually needs location granted AND on.
    PermissionStatus? location;
    if (classic || !scan.isGranted) {
      location = await Permission.locationWhenInUse.request();
    }
    if (classic) {
      if (!connect.isGranted) {
        throw StateError('请授予「附近的设备 / 蓝牙」连接权限');
      }
      if (!scan.isGranted && location?.isGranted != true) {
        throw StateError('经典蓝牙扫描需要「附近的设备」或「位置」权限，并打开系统定位');
      }
      return;
    }
    if (scan.isGranted && connect.isGranted) return;
    if (location?.isGranted == true) return;
    throw StateError('蓝牙权限被拒绝，可在系统设置中打开');
  }

  String _markName(int which) {
    const names = ['CHARGE', 'DRY END', 'FCs', 'FCe', 'SCs', 'SCe', 'DROP', 'COOL END'];
    return which >= 0 && which < names.length ? names[which] : '事件';
  }

  String _markCommand(int which) {
    switch (which) {
      case RoastProfile.charge:
        return 'charge';
      case RoastProfile.dry:
        return 'dry';
      case RoastProfile.fcs:
        return 'fcs';
      case RoastProfile.scs:
        return 'scs';
      case RoastProfile.drop:
        return 'drop';
      default:
        return 'mark';
    }
  }

  @override
  void dispose() {
    _alive = false;
    _timer?.cancel();
    unawaited(session.disconnect());
    super.dispose();
  }
}
