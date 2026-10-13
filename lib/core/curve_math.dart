import 'dart:math' as math;

import '../models/roast_models.dart';

class RoastStats {
  const RoastStats({
    this.roastTime,
    this.dryTime,
    this.maillardTime,
    this.developmentTime,
    this.dtr,
    this.chargeBt,
    this.dryBt,
    this.fcsBt,
    this.dropBt,
    this.tpFromCharge,
    this.tpBt,
    this.auc,
    this.weightLoss,
  });

  final double? roastTime;
  final double? dryTime;
  final double? maillardTime;
  final double? developmentTime;
  final double? dtr;
  final double? chargeBt;
  final double? dryBt;
  final double? fcsBt;
  final double? dropBt;
  final double? tpFromCharge;
  final double? tpBt;
  final double? auc;
  final double? weightLoss;
}

List<double?> rateOfRise(
  List<Sample> samples,
  bool bean, {
  required double spanSeconds,
  int smooth = 3,
  int? from,
  int? until,
}) {
  final n = samples.length;
  final raw = List<double?>.filled(n, null);
  if (n == 0 || spanSeconds <= 0) return raw;
  for (var i = 0; i < n; i++) {
    if (from != null && i < from) continue;
    if (until != null && i > until) continue;
    final y1 = bean ? samples[i].bt : samples[i].et;
    if (y1 <= 0) continue;
    var j = i;
    while (j > 0 && samples[i].t - samples[j - 1].t <= spanSeconds) {
      j--;
    }
    if (j == i) continue;
    final y0 = bean ? samples[j].bt : samples[j].et;
    final dt = samples[i].t - samples[j].t;
    if (y0 <= 0 || dt < 0.2) continue;
    raw[i] = (y1 - y0) / dt * 60.0;
  }
  if (smooth <= 1) return raw;
  final out = List<double?>.filled(n, null);
  for (var i = 0; i < n; i++) {
    if (raw[i] == null) continue;
    var acc = 0.0;
    var count = 0;
    for (var k = math.max(0, i - smooth + 1); k <= i; k++) {
      final v = raw[k];
      if (v == null) continue;
      acc += v;
      count++;
    }
    if (count > 0) out[i] = acc / count;
  }
  return out;
}

int? detectTurningPoint(List<Sample> samples, int charge, {double window = 120}) {
  if (charge < 0 || charge >= samples.length) return null;
  final limit = samples[charge].t + window;
  var minI = charge;
  var minV = samples[charge].bt;
  var rose = false;
  for (var i = charge + 1; i < samples.length; i++) {
    if (samples[i].t > limit && minI != charge) break;
    if (!samples[i].btOk) continue;
    if (samples[i].bt < minV) {
      minV = samples[i].bt;
      minI = i;
      rose = false;
    } else if (minI != charge && samples[i].bt > minV + 0.6) {
      rose = true;
      break;
    }
  }
  if (rose && minI != charge) return minI;
  return null;
}

double? areaUnderCurve(
  List<Sample> samples, {
  required int from,
  required int until,
  required double baseCelsius,
}) {
  if (from < 0 || until <= from || until >= samples.length) return null;
  var area = 0.0;
  for (var i = from + 1; i <= until; i++) {
    final dt = (samples[i].t - samples[i - 1].t) / 60.0;
    if (dt <= 0) continue;
    final a = math.max(0.0, samples[i - 1].bt - baseCelsius);
    final b = math.max(0.0, samples[i].bt - baseCelsius);
    if (samples[i - 1].bt <= 0 || samples[i].bt <= 0) continue;
    area += (a + b) / 2 * dt;
  }
  return area;
}

RoastStats computeStats(
  RoastProfile profile, {
  required double aucBase,
}) {
  double? between(int a, int b) {
    final sa = profile.sampleAt(a);
    final sb = profile.sampleAt(b);
    if (sa == null || sb == null) return null;
    return sb.t - sa.t;
  }

  final roast = between(RoastProfile.charge, RoastProfile.drop);
  final dry = between(RoastProfile.charge, RoastProfile.dry);
  final maillard = between(RoastProfile.dry, RoastProfile.fcs);
  final dev = between(RoastProfile.fcs, RoastProfile.drop);
  final charge = profile.sampleAt(RoastProfile.charge);
  final tp = profile.tpIndex >= 0 && profile.tpIndex < profile.samples.length
      ? profile.samples[profile.tpIndex]
      : null;
  double? loss;
  if (profile.weightIn > 0 && profile.weightOut > 0) {
    loss = (profile.weightIn - profile.weightOut) / profile.weightIn * 100;
  }
  final dropIndex = profile.indexOf(RoastProfile.drop);
  final end = dropIndex >= 0
      ? dropIndex
      : (profile.samples.isEmpty ? -1 : profile.samples.length - 1);
  return RoastStats(
    roastTime: roast,
    dryTime: dry,
    maillardTime: maillard,
    developmentTime: dev,
    dtr: (roast != null && dev != null && roast > 0) ? dev / roast * 100 : null,
    chargeBt: charge?.bt,
    dryBt: profile.sampleAt(RoastProfile.dry)?.bt,
    fcsBt: profile.sampleAt(RoastProfile.fcs)?.bt,
    dropBt: profile.sampleAt(RoastProfile.drop)?.bt,
    tpFromCharge: (tp != null && charge != null) ? tp.t - charge.t : null,
    tpBt: tp?.bt,
    auc: areaUnderCurve(
      profile.samples,
      from: profile.indexOf(RoastProfile.charge),
      until: end,
      baseCelsius: aucBase,
    ),
    weightLoss: loss,
  );
}

/// Linear BT projection. Returns (slope °C/s, intercept) over the recent window.
(double slope, double intercept)? projectBt(List<Sample> samples, {double window = 20}) {
  if (samples.length < 4) return null;
  final end = samples.last.t;
  final pts = samples.where((s) => s.btOk && end - s.t <= window).toList();
  if (pts.length < 4) return null;
  var n = 0.0;
  var sx = 0.0;
  var sy = 0.0;
  var sxx = 0.0;
  var sxy = 0.0;
  for (final p in pts) {
    n += 1;
    sx += p.t;
    sy += p.bt;
    sxx += p.t * p.t;
    sxy += p.t * p.bt;
  }
  final den = n * sxx - sx * sx;
  if (den.abs() < 1e-6) return null;
  final slope = (n * sxy - sx * sy) / den;
  final intercept = (sy - slope * sx) / n;
  return (slope, intercept);
}
