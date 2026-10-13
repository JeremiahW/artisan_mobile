import 'dart:convert';

import '../models/roast_models.dart';

RoastProfile decodeProfileText(String raw) {
  final text = raw.trim();
  if (text.isEmpty) {
    throw const FormatException('空文件');
  }
  if (text.startsWith('{') && text.contains('"samples"')) {
    return RoastProfile.fromJson(
      Map<String, dynamic>.from(jsonDecode(text) as Map),
    );
  }
  if (_looksLikeCsv(text)) {
    return decodeArtisanCsv(text);
  }
  if (text.startsWith('{')) {
    return decodeArtisanAlog(text);
  }
  throw const FormatException('无法识别的曲线文件');
}

bool _looksLikeCsv(String text) {
  final head = text.length > 800 ? text.substring(0, 800) : text;
  return head.contains('Time1') || head.contains('Unit:') || head.contains('\tET\t');
}

RoastProfile decodeArtisanAlog(String src) {
  final timex = _numberList(src, 'timex');
  final et = _numberList(src, 'temp1');
  final bt = _numberList(src, 'temp2');
  if (timex == null || et == null || bt == null) {
    throw const FormatException('曲线文件里没有 timex / temp1 / temp2');
  }
  final n = [timex.length, et.length, bt.length].reduce((a, b) => a < b ? a : b);
  final samples = <Sample>[
    for (var i = 0; i < n; i++) Sample(t: timex[i], et: et[i], bt: bt[i]),
  ];
  final index = _numberList(src, 'timeindex')?.map((e) => e.round()).toList() ??
      List<int>.filled(8, -1);
  while (index.length < 8) {
    index.add(-1);
  }
  final eventTimes = _numberList(src, 'specialevents') ?? const <double>[];
  final eventTypes = _numberList(src, 'specialeventstype') ?? const <double>[];
  final eventValues = _numberList(src, 'specialeventsvalue') ?? const <double>[];
  final eventLabels = _stringList(src, 'specialeventsStrings');
  final events = <RoastEvent>[];
  for (var i = 0; i < eventTimes.length; i++) {
    events.add(RoastEvent(
      t: eventTimes[i],
      type: i < eventTypes.length ? eventTypes[i].round() : 4,
      value: i < eventValues.length ? eventValues[i] : 0,
      description: i < eventLabels.length ? eventLabels[i] : '',
    ));
  }
  final weight = _weight(src);
  return RoastProfile(
    title: _stringField(src, 'title') ?? '导入曲线',
    beans: _stringField(src, 'beans') ?? '',
    operatorName: _stringField(src, 'operator') ?? '',
    machine: _stringField(src, 'roastertype') ?? _stringField(src, 'machine') ?? '',
    notes: _stringField(src, 'roastingnotes') ?? _stringField(src, 'notes') ?? '',
    weightIn: weight.$1,
    weightOut: weight.$2,
    mode: _stringField(src, 'mode') ?? 'C',
    samples: samples,
    timeindex: index,
    events: events,
  );
}

RoastProfile decodeArtisanCsv(String src) {
  final lines = const LineSplitter().convert(src).where((l) => l.trim().isNotEmpty).toList();
  if (lines.length < 2) {
    throw const FormatException('CSV 内容不足');
  }
  var headerIndex = lines.indexWhere((l) => l.contains('Time1') && l.contains('BT'));
  if (headerIndex < 0) headerIndex = 1;
  final meta = headerIndex > 0 ? lines[headerIndex - 1] : lines.first;
  final fields = lines[headerIndex].split('\t');
  final etCol = fields.indexOf('ET');
  final btCol = fields.indexOf('BT');
  final timeCol = fields.indexOf('Time1');
  if (etCol < 0 || btCol < 0 || timeCol < 0) {
    throw const FormatException('CSV 缺少 Time1 / ET / BT 列');
  }
  final samples = <Sample>[];
  for (final line in lines.skip(headerIndex + 1)) {
    final cells = line.split('\t');
    if (cells.length <= btCol || cells.length <= etCol) continue;
    final t = _parseClock(cells[timeCol]);
    final et = double.tryParse(cells[etCol]);
    final bt = double.tryParse(cells[btCol]);
    if (t == null || et == null || bt == null) continue;
    if (samples.isNotEmpty && t <= samples.last.t) continue;
    samples.add(Sample(t: t, et: et, bt: bt));
  }
  final index = List<int>.filled(8, -1);
  const marks = ['CHARGE:', 'DRYe:', 'FCs:', 'FCe:', 'SCs:', 'SCe:', 'DROP:', 'COOL:'];
  for (var i = 0; i < marks.length; i++) {
    final seconds = _metaSeconds(meta, marks[i]);
    if (seconds == null || samples.isEmpty) continue;
    var best = 0;
    var bestDiff = double.infinity;
    for (var s = 0; s < samples.length; s++) {
      final d = (samples[s].t - seconds).abs();
      if (d < bestDiff) {
        bestDiff = d;
        best = s;
      }
    }
    if (bestDiff < 2) index[i] = best;
  }
  final unit = RegExp(r'Unit:([CF])').firstMatch(meta)?.group(1) ?? 'C';
  return RoastProfile(
    title: 'CSV 导入',
    mode: unit,
    samples: samples,
    timeindex: index,
  );
}

String encodeArtisanCsv(RoastProfile profile) {
  String mark(int which) {
    final sample = profile.sampleAt(which);
    if (sample == null) return '';
    final charge = profile.sampleAt(RoastProfile.charge);
    final t = charge == null ? sample.t : sample.t - charge.t;
    return formatClock(t);
  }

  final date = profile.roastDate;
  final dateText =
      '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  final timeText =
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
  final header = [
    'Date:$dateText',
    'Unit:${profile.mode}',
    'CHARGE:${mark(RoastProfile.charge)}',
    '',
    'DRYe:${mark(RoastProfile.dry)}',
    'FCs:${mark(RoastProfile.fcs)}',
    'FCe:${mark(RoastProfile.fce)}',
    'SCs:${mark(RoastProfile.scs)}',
    'SCe:${mark(RoastProfile.sce)}',
    'DROP:${mark(RoastProfile.drop)}',
    'COOL:${mark(RoastProfile.cool)}',
    'Time:$timeText',
  ].join('\t');
  final rows = <String>['Time1\tTime2\tET\tBT\tEvent'];
  final charge = profile.sampleAt(RoastProfile.charge);
  for (final s in profile.samples) {
    final fromCharge = charge == null ? s.t : s.t - charge.t;
    rows.add('${s.t.toStringAsFixed(1)}\t${fromCharge.toStringAsFixed(1)}\t${s.et.toStringAsFixed(1)}\t${s.bt.toStringAsFixed(1)}\t');
  }
  return '$header\n${rows.join('\n')}\n';
}

List<double>? _numberList(String src, String key) {
  final match = RegExp("['\\\"]$key['\\\"]\\s*:\\s*\\[").firstMatch(src);
  if (match == null) return null;
  final start = match.end;
  final end = src.indexOf(']', start);
  if (end < 0) return null;
  final body = src.substring(start, end).trim();
  if (body.isEmpty) return <double>[];
  return body.split(',').map((part) {
    final t = part.trim();
    if (t == 'None' || t == 'null') return -1.0;
    return double.tryParse(t) ?? -1.0;
  }).toList();
}

List<String> _stringList(String src, String key) {
  final match = RegExp("['\\\"]$key['\\\"]\\s*:\\s*\\[").firstMatch(src);
  if (match == null) return const [];
  final start = match.end;
  final end = src.indexOf(']', start);
  if (end < 0) return const [];
  return RegExp("'((?:\\\\'|[^'])*)'|\"((?:\\\\\"|[^\"])*)\"")
      .allMatches(src.substring(start, end))
      .map((m) => (m.group(1) ?? m.group(2) ?? '').replaceAll("\\'", "'"))
      .toList();
}

String? _stringField(String src, String key) {
  final match = RegExp("['\\\"]$key['\\\"]\\s*:\\s*'((?:\\\\'|[^'])*)'|['\\\"]$key['\\\"]\\s*:\\s*\"((?:\\\\\"|[^\"])*)\"")
      .firstMatch(src);
  if (match == null) return null;
  return (match.group(1) ?? match.group(2) ?? '').replaceAll("\\'", "'");
}

(double, double) _weight(String src) {
  final match = RegExp(
    "['\\\"]weight['\\\"]\\s*:\\s*\\(\\s*['\\\"][^'\\\"]+['\\\"]\\s*,\\s*([0-9.]+)\\s*,\\s*([0-9.]+)",
  ).firstMatch(src);
  if (match == null) return (0, 0);
  return (
    double.tryParse(match.group(1) ?? '') ?? 0,
    double.tryParse(match.group(2) ?? '') ?? 0,
  );
}

double? _parseClock(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  if (text.contains(':')) {
    final parts = text.split(':');
    if (parts.length < 2) return null;
    final m = int.tryParse(parts[0]) ?? 0;
    final s = double.tryParse(parts[1]) ?? 0;
    return m * 60 + s;
  }
  return double.tryParse(text);
}

double? _metaSeconds(String meta, String label) {
  final index = meta.indexOf(label);
  if (index < 0) return null;
  final rest = meta.substring(index + label.length).split('\t').first.trim();
  if (rest.isEmpty) return null;
  return _parseClock(rest);
}
