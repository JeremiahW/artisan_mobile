class Sample {
  const Sample({
    required this.t,
    required this.et,
    required this.bt,
    this.sv,
    this.power,
    this.fan,
    this.drum,
  });

  final double t;
  final double et;
  final double bt;
  final double? sv;
  final double? power;
  final double? fan;
  final double? drum;

  bool get etOk => et > 0 && et < 900;
  bool get btOk => bt > 0 && bt < 900;
  bool get svOk => sv != null && sv! > 0 && sv! < 900;

  Map<String, dynamic> toJson() => {
        't': t,
        'et': et,
        'bt': bt,
        if (sv != null) 'sv': sv,
        if (power != null) 'power': power,
        if (fan != null) 'fan': fan,
        if (drum != null) 'drum': drum,
      };

  factory Sample.fromJson(Map<String, dynamic> json) => Sample(
        t: (json['t'] as num).toDouble(),
        et: (json['et'] as num).toDouble(),
        bt: (json['bt'] as num).toDouble(),
        sv: (json['sv'] as num?)?.toDouble(),
        power: (json['power'] as num?)?.toDouble(),
        fan: (json['fan'] as num?)?.toDouble(),
        drum: (json['drum'] as num?)?.toDouble(),
      );
}

class RoastEvent {
  const RoastEvent({
    required this.t,
    required this.type,
    required this.value,
    this.description = '',
  });

  final double t;
  final int type;
  final double value;
  final String description;

  Map<String, dynamic> toJson() => {
        't': t,
        'type': type,
        'value': value,
        'description': description,
      };

  factory RoastEvent.fromJson(Map<String, dynamic> json) => RoastEvent(
        t: (json['t'] as num).toDouble(),
        type: (json['type'] as num).toInt(),
        value: (json['value'] as num).toDouble(),
        description: json['description'] as String? ?? '',
      );
}

enum AlarmSource { time, et, bt, deltaEt, deltaBt }

enum AlarmCompare { above, below }

enum AlarmAction { popup, setSlider }

class AlarmRule {
  AlarmRule({
    required this.id,
    this.enabled = true,
    this.guardSeconds = 0,
    this.source = AlarmSource.bt,
    this.compare = AlarmCompare.above,
    this.threshold = 200,
    this.action = AlarmAction.popup,
    this.slider = 2,
    this.actionValue = 80,
    this.description = '',
    this.fired = false,
  });

  final String id;
  bool enabled;
  double guardSeconds;
  AlarmSource source;
  AlarmCompare compare;
  double threshold;
  AlarmAction action;
  int slider;
  double actionValue;
  String description;
  bool fired;

  Map<String, dynamic> toJson() => {
        'id': id,
        'enabled': enabled,
        'guardSeconds': guardSeconds,
        'source': source.name,
        'compare': compare.name,
        'threshold': threshold,
        'action': action.name,
        'slider': slider,
        'actionValue': actionValue,
        'description': description,
      };

  factory AlarmRule.fromJson(Map<String, dynamic> json) => AlarmRule(
        id: json['id'] as String? ?? 'a',
        enabled: json['enabled'] as bool? ?? true,
        guardSeconds: (json['guardSeconds'] as num?)?.toDouble() ?? 0,
        source: AlarmSource.values.byName(json['source'] as String? ?? 'bt'),
        compare: AlarmCompare.values.byName(json['compare'] as String? ?? 'above'),
        threshold: (json['threshold'] as num?)?.toDouble() ?? 200,
        action: AlarmAction.values.byName(json['action'] as String? ?? 'popup'),
        slider: (json['slider'] as num?)?.toInt() ?? 2,
        actionValue: (json['actionValue'] as num?)?.toDouble() ?? 80,
        description: json['description'] as String? ?? '',
      );
}

class EventButton {
  EventButton({
    required this.label,
    required this.type,
    required this.value,
    this.description = '',
    this.action = 0,
    this.command = '',
    this.step = 0,
  });

  String label;
  int type;
  double value;
  String description;
  /// Artisan action: 0 none / slider, 1 serial, 20 artisan command, …
  int action;
  String command;
  /// Relative step for UP/DOWN style buttons (e.g. ±5).
  double step;

  Map<String, dynamic> toJson() => {
        'label': label,
        'type': type,
        'value': value,
        'description': description,
        'action': action,
        'command': command,
        'step': step,
      };

  factory EventButton.fromJson(Map<String, dynamic> json) => EventButton(
        label: json['label'] as String? ?? '',
        type: (json['type'] as num?)?.toInt() ?? 2,
        value: (json['value'] as num?)?.toDouble() ?? 0,
        description: json['description'] as String? ?? '',
        action: (json['action'] as num?)?.toInt() ?? 0,
        command: json['command'] as String? ?? '',
        step: (json['step'] as num?)?.toDouble() ?? 0,
      );
}

class Reading {
  const Reading({
    this.et = -1,
    this.bt = -1,
    this.power,
    this.fan,
    this.drum,
    this.weight,
    this.setpoint,
    this.note = '',
  });

  final double et;
  final double bt;
  final int? power;
  final int? fan;
  final int? drum;
  final double? weight;
  final double? setpoint;
  final String note;

  bool get hasTemp => et > 0 || bt > 0;
}

class RoastProfile {
  RoastProfile({
    this.title = '未命名',
    this.beans = '',
    this.operatorName = '',
    this.machine = '',
    this.notes = '',
    this.weightIn = 0,
    this.weightOut = 0,
    this.moisture = 0,
    this.color = 0,
    this.mode = 'C',
    DateTime? roastDate,
    List<Sample>? samples,
    List<int>? timeindex,
    List<RoastEvent>? events,
    List<double>? flavors,
    this.cuppingNotes = '',
    this.tpIndex = -1,
  })  : roastDate = roastDate ?? DateTime.now(),
        samples = samples ?? <Sample>[],
        timeindex = timeindex ?? List<int>.filled(8, -1),
        events = events ?? <RoastEvent>[],
        flavors = flavors ?? List<double>.filled(10, 7);

  String title;
  String beans;
  String operatorName;
  String machine;
  String notes;
  double weightIn;
  double weightOut;
  double moisture;
  int color;
  String mode;
  DateTime roastDate;
  final List<Sample> samples;
  final List<int> timeindex;
  final List<RoastEvent> events;
  final List<double> flavors;
  String cuppingNotes;
  int tpIndex;

  static const charge = 0;
  static const dry = 1;
  static const fcs = 2;
  static const fce = 3;
  static const scs = 4;
  static const sce = 5;
  static const drop = 6;
  static const cool = 7;

  int indexOf(int mark) =>
      mark >= 0 && mark < timeindex.length ? timeindex[mark] : -1;

  Sample? sampleAt(int mark) {
    final i = indexOf(mark);
    if (i < 0 || i >= samples.length) return null;
    return samples[i];
  }

  void clearCurve() {
    samples.clear();
    events.clear();
    for (var i = 0; i < timeindex.length; i++) {
      timeindex[i] = -1;
    }
    tpIndex = -1;
  }

  Map<String, dynamic> toJson() => {
        'format': 'artisan-flutter',
        'version': 1,
        'title': title,
        'beans': beans,
        'operator': operatorName,
        'machine': machine,
        'notes': notes,
        'weightIn': weightIn,
        'weightOut': weightOut,
        'moisture': moisture,
        'color': color,
        'mode': mode,
        'roastDate': roastDate.toIso8601String(),
        'samples': samples.map((e) => e.toJson()).toList(),
        'timeindex': timeindex,
        'events': events.map((e) => e.toJson()).toList(),
        'flavors': flavors,
        'cuppingNotes': cuppingNotes,
        'tpIndex': tpIndex,
      };

  factory RoastProfile.fromJson(Map<String, dynamic> json) {
    final samples = (json['samples'] as List<dynamic>? ?? [])
        .map((e) => Sample.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final index = (json['timeindex'] as List<dynamic>? ?? [])
        .map((e) => (e as num).toInt())
        .toList();
    while (index.length < 8) {
      index.add(-1);
    }
    final flavors = (json['flavors'] as List<dynamic>? ?? [])
        .map((e) => (e as num).toDouble())
        .toList();
    while (flavors.length < 10) {
      flavors.add(7);
    }
    return RoastProfile(
      title: json['title'] as String? ?? '未命名',
      beans: json['beans'] as String? ?? '',
      operatorName: json['operator'] as String? ?? '',
      machine: json['machine'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      weightIn: (json['weightIn'] as num?)?.toDouble() ?? 0,
      weightOut: (json['weightOut'] as num?)?.toDouble() ?? 0,
      moisture: (json['moisture'] as num?)?.toDouble() ?? 0,
      color: (json['color'] as num?)?.toInt() ?? 0,
      mode: json['mode'] as String? ?? 'C',
      roastDate: DateTime.tryParse(json['roastDate'] as String? ?? '') ??
          DateTime.now(),
      samples: samples,
      timeindex: index,
      events: (json['events'] as List<dynamic>? ?? [])
          .map((e) => RoastEvent.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      flavors: flavors,
      cuppingNotes: json['cuppingNotes'] as String? ?? '',
      tpIndex: (json['tpIndex'] as num?)?.toInt() ?? -1,
    );
  }
}

const flavorLabels = <String>[
  '干香',
  '湿香',
  '风味',
  '余韵',
  '酸质',
  '甜感',
  '口感',
  '平衡',
  '一致性',
  '干净度',
];

const eventTypeLabels = <String>['气流', '滚筒', '火力', '风门'];

String formatClock(double seconds) {
  if (seconds.isNaN || seconds.isInfinite) return '--:--';
  var s = seconds.round();
  if (s < 0) s = 0;
  final m = s ~/ 60;
  final r = s % 60;
  return '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
}

double displayTemp(double celsius, String mode) {
  if (celsius <= 0 || celsius >= 900) return celsius;
  if (mode == 'F') return celsius * 9 / 5 + 32;
  return celsius;
}

double displayRor(double cPerMin, String mode) {
  if (mode == 'F') return cPerMin * 9 / 5;
  return cPerMin;
}

double toCelsius(double displayed, String mode) {
  if (mode == 'F') return (displayed - 32) * 5 / 9;
  return displayed;
}
