import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/curve_math.dart';
import '../models/roast_models.dart';
import '../state/roast_controller.dart';
import '../theme/artisan_theme.dart';

class RoastChart extends StatelessWidget {
  const RoastChart({super.key, required this.controller});

  final RoastController controller;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RoastPainter(controller),
      child: const SizedBox.expand(),
    );
  }
}

class _RoastPainter extends CustomPainter {
  _RoastPainter(this.controller);

  final RoastController controller;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 48.0;
    const right = 46.0;
    const top = 18.0;
    const bottom = 32.0;
    final plot = Rect.fromLTWH(left, top, math.max(10, size.width - left - right), math.max(10, size.height - top - bottom));
    canvas.drawRect(Offset.zero & size, Paint()..color = ArtisanColors.canvas);
    canvas.drawRect(plot, Paint()..color = ArtisanColors.plot);

    final samples = controller.profile.samples;
    final lastT = samples.isEmpty ? 0.0 : samples.last.t;
    final xMaxMin = math.max(8.0, lastT / 60 + 0.4);
    final temps = <double>[
      for (final s in samples) ...[
        if (s.etOk) s.et,
        if (s.btOk) s.bt,
        if (controller.showSv && s.svOk) s.sv!,
      ],
      if (controller.showSv && controller.pidSv > 0) controller.pidSv,
    ];
    var tempMin = temps.isEmpty ? 50.0 : temps.reduce(math.min) - 8;
    var tempMax = temps.isEmpty ? 250.0 : temps.reduce(math.max) + 12;
    if (tempMax - tempMin < 40) tempMax = tempMin + 40;
    final etRor = controller.etRor;
    final btRor = controller.btRor;
    final rors = <double>[
      for (final v in [...etRor, ...btRor]) ?v,
    ];
    var rorMin = rors.isEmpty ? 0.0 : math.min(0, rors.reduce(math.min) - 2).toDouble();
    var rorMax = rors.isEmpty ? 25.0 : math.max(20, rors.reduce(math.max) + 2).toDouble();

    double xOf(double seconds) => plot.left + (seconds / 60) / xMaxMin * plot.width;
    double yTemp(double c) => plot.top + (tempMax - c) / (tempMax - tempMin) * plot.height;
    double yRor(double r) => plot.top + (rorMax - r) / (rorMax - rorMin) * plot.height;

    _bands(canvas, plot, xOf, samples);
    _grid(canvas, plot, xMaxMin, tempMin, tempMax, xOf, yTemp);
    if (controller.showBackground) {
      _background(canvas, xOf, yTemp);
    }
    if (controller.showEt) {
      _line(canvas, samples, xOf, yTemp, (s) => s.etOk ? s.et : null, ArtisanColors.et, 2.2);
    }
    if (controller.showBt) {
      _line(canvas, samples, xOf, yTemp, (s) => s.btOk ? s.bt : null, ArtisanColors.bt, 2.6);
    }
    if (controller.showSv) {
      _line(canvas, samples, xOf, yTemp, (s) => s.svOk ? s.sv : null, ArtisanColors.sv, 1.8);
    }
    if (controller.showDeltaEt) {
      _ror(canvas, samples, etRor, xOf, yRor, ArtisanColors.et.withValues(alpha: 0.55));
    }
    if (controller.showDeltaBt) {
      _ror(canvas, samples, btRor, xOf, yRor, ArtisanColors.bt.withValues(alpha: 0.8));
    }
    _events(canvas, plot, xOf, yTemp);
    _milestones(canvas, plot, xOf, yTemp);
    _projection(canvas, plot, xOf, yTemp);
    _axes(canvas, plot, xMaxMin, tempMin, tempMax, rorMin, rorMax, yTemp, yRor);
    if (controller.recording && samples.isNotEmpty) {
      final x = xOf(samples.last.t);
      canvas.drawLine(
        Offset(x, plot.top),
        Offset(x, plot.bottom),
        Paint()
          ..color = ArtisanColors.bt.withValues(alpha: 0.35)
          ..strokeWidth = 1,
      );
    }
  }

  void _bands(Canvas canvas, Rect plot, double Function(double) xOf, List<Sample> samples) {
    final profile = controller.profile;
    final charge = profile.sampleAt(RoastProfile.charge);
    if (charge == null) return;
    final dry = profile.sampleAt(RoastProfile.dry) ?? _crossing(samples, profile.indexOf(RoastProfile.charge), controller.dryTemp);
    final fcs = profile.sampleAt(RoastProfile.fcs) ?? _crossing(samples, profile.indexOf(RoastProfile.dry), controller.fcsTemp);
    final drop = profile.sampleAt(RoastProfile.drop) ?? (controller.recording ? samples.last : null);
    void band(Sample? a, Sample? b, Color color) {
      if (a == null || b == null || b.t <= a.t) return;
      final rect = Rect.fromLTRB(xOf(a.t), plot.top, xOf(b.t), plot.bottom);
      canvas.drawRect(rect, Paint()..color = color);
    }

    band(charge, dry, ArtisanColors.phaseDry);
    band(dry, fcs, ArtisanColors.phaseMaillard);
    band(fcs, drop, ArtisanColors.phaseDev);
  }

  Sample? _crossing(List<Sample> samples, int from, double temp) {
    if (from < 0) return null;
    for (var i = from; i < samples.length; i++) {
      if (samples[i].btOk && samples[i].bt >= temp) return samples[i];
    }
    return null;
  }

  void _grid(Canvas canvas, Rect plot, double xMaxMin, double tempMin, double tempMax, double Function(double) xOf, double Function(double) yTemp) {
    final paint = Paint()
      ..color = ArtisanColors.grid
      ..strokeWidth = 1;
    final text = TextPainter(textDirection: TextDirection.ltr);
    for (var minute = 0.0; minute <= xMaxMin + 0.01; minute += xMaxMin > 16 ? 2 : 1) {
      final x = xOf(minute * 60);
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), paint);
      _label(canvas, text, minute.toStringAsFixed(0), Offset(x - 6, plot.bottom + 4), ArtisanColors.axis, 11);
    }
    final step = (tempMax - tempMin) > 160 ? 20.0 : 10.0;
    var temp = (tempMin / step).ceil() * step;
    while (temp < tempMax) {
      final y = yTemp(temp);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), paint);
      _label(canvas, text, temp.toStringAsFixed(0), Offset(2, y - 7), ArtisanColors.axis, 11);
      temp += step;
    }
  }

  void _background(Canvas canvas, double Function(double) xOf, double Function(double) yTemp) {
    final bg = controller.background;
    if (bg == null || bg.samples.isEmpty) return;
    var shift = 0.0;
    if (controller.alignBackground) {
      final fg = controller.profile.sampleAt(RoastProfile.charge);
      final start = bg.sampleAt(RoastProfile.charge);
      if (fg != null && start != null) shift = fg.t - start.t;
    }
    _dashed(
      canvas,
      bg.samples,
      (s) => xOf(s.t + shift),
      (s) => s.etOk ? yTemp(s.et) : null,
      ArtisanColors.et.withValues(alpha: 0.45),
    );
    _dashed(
      canvas,
      bg.samples,
      (s) => xOf(s.t + shift),
      (s) => s.btOk ? yTemp(s.bt) : null,
      ArtisanColors.bt.withValues(alpha: 0.45),
    );
  }

  void _line(
    Canvas canvas,
    List<Sample> samples,
    double Function(double) xOf,
    double Function(double) yOf,
    double? Function(Sample) pick,
    Color color,
    double width,
  ) {
    final path = Path();
    var drawing = false;
    for (final sample in samples) {
      final value = pick(sample);
      if (value == null) {
        drawing = false;
        continue;
      }
      final point = Offset(xOf(sample.t), yOf(value));
      if (!drawing) {
        path.moveTo(point.dx, point.dy);
        drawing = true;
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
  }

  void _ror(Canvas canvas, List<Sample> samples, List<double?> ror, double Function(double) xOf, double Function(double) yOf, Color color) {
    final path = Path();
    var drawing = false;
    for (var i = 0; i < samples.length && i < ror.length; i++) {
      final value = ror[i];
      if (value == null) {
        drawing = false;
        continue;
      }
      final point = Offset(xOf(samples[i].t), yOf(value));
      if (!drawing) {
        path.moveTo(point.dx, point.dy);
        drawing = true;
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
  }

  void _dashed(Canvas canvas, List<Sample> samples, double Function(Sample) xOf, double? Function(Sample) yOf, Color color) {
    final path = Path();
    var drawing = false;
    for (final sample in samples) {
      final y = yOf(sample);
      if (y == null) {
        drawing = false;
        continue;
      }
      final point = Offset(xOf(sample), y);
      if (!drawing) {
        path.moveTo(point.dx, point.dy);
        drawing = true;
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + 7, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + 4;
      }
    }
  }

  void _events(Canvas canvas, Rect plot, double Function(double) xOf, double Function(double) yTemp) {
    final text = TextPainter(textDirection: TextDirection.ltr);
    for (final event in controller.profile.events) {
      if (event.type < 0 || event.type > 3) continue;
      final x = xOf(event.t);
      final color = ArtisanColors.eventColors[event.type];
      canvas.drawLine(Offset(x, plot.bottom - 28), Offset(x, plot.bottom), Paint()..color = color..strokeWidth = 2);
      _label(canvas, text, event.value.round().toString(), Offset(x + 2, plot.bottom - 42), color, 10);
    }
  }

  void _milestones(Canvas canvas, Rect plot, double Function(double) xOf, double Function(double) yTemp) {
    const names = ['CHARGE', 'DRY', 'FCs', 'FCe', 'SCs', 'SCe', 'DROP', 'COOL'];
    final text = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i < names.length; i++) {
      final sample = controller.profile.sampleAt(i);
      if (sample == null) continue;
      final x = xOf(sample.t);
      final y = sample.btOk ? yTemp(sample.bt) : plot.center.dy;
      canvas.drawCircle(Offset(x, y), 3.5, Paint()..color = Colors.black);
      _label(canvas, text, names[i], Offset(x + 4, y - 16), Colors.black, 11);
    }
    final tp = controller.profile.tpIndex;
    if (tp >= 0 && tp < controller.profile.samples.length) {
      final sample = controller.profile.samples[tp];
      if (sample.btOk) {
        final point = Offset(xOf(sample.t), yTemp(sample.bt));
        canvas.drawCircle(point, 3, Paint()..color = ArtisanColors.title);
        _label(canvas, text, 'TP', point + const Offset(4, 2), ArtisanColors.title, 11);
      }
    }
  }

  void _projection(Canvas canvas, Rect plot, double Function(double) xOf, double Function(double) yTemp) {
    if (!controller.recording) return;
    final fit = projectBt(controller.profile.samples);
    if (fit == null) return;
    final last = controller.profile.samples.last;
    final ahead = last.t + 60;
    final y1 = fit.$2 + fit.$1 * last.t;
    final y2 = fit.$2 + fit.$1 * ahead;
    final paint = Paint()
      ..color = ArtisanColors.bt.withValues(alpha: 0.45)
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(xOf(last.t), yTemp(y1)), Offset(xOf(ahead).clamp(plot.left, plot.right).toDouble(), yTemp(y2)), paint);
    if (fit.$1 > 0.01) {
      final seconds = (controller.targetTemp - last.bt) / fit.$1;
      if (seconds > 0 && seconds < 30 * 60) {
        final text = TextPainter(textDirection: TextDirection.ltr);
        _label(
          canvas,
          text,
          '到达 ${controller.targetTemp.toStringAsFixed(0)}° 约 ${formatClock(seconds)}',
          Offset(plot.left + 8, plot.top + 6),
          ArtisanColors.title,
          12,
        );
      }
    }
  }

  void _axes(Canvas canvas, Rect plot, double xMaxMin, double tempMin, double tempMax, double rorMin, double rorMax, double Function(double) yTemp, double Function(double) yRor) {
    final border = Paint()
      ..color = const Color(0xFFBDBDBD)
      ..style = PaintingStyle.stroke;
    canvas.drawRect(plot, border);
    final text = TextPainter(textDirection: TextDirection.ltr);
    _label(canvas, text, '0', Offset(plot.right - 28, plot.top + 2), ArtisanColors.bt, 10);
    _label(canvas, text, rorMax.toStringAsFixed(0), Offset(plot.right + 4, plot.top), ArtisanColors.bt, 10);
    _label(canvas, text, rorMin.toStringAsFixed(0), Offset(plot.right + 4, plot.bottom - 12), ArtisanColors.bt, 10);
    _label(canvas, text, controller.mode == 'F' ? '°F' : '°C', Offset(4, plot.top - 2), ArtisanColors.axis, 10);
  }

  void _label(Canvas canvas, TextPainter painter, String value, Offset offset, Color color, double size) {
    painter.text = TextSpan(text: value, style: TextStyle(color: color, fontSize: size, fontWeight: FontWeight.w600));
    painter.layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _RoastPainter oldDelegate) => true;
}
