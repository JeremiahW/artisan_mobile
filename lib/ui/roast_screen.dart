import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../devices/device_catalog.dart';
import '../models/roast_models.dart';
import '../state/roast_controller.dart';
import '../theme/artisan_theme.dart';
import 'dialogs.dart';
import 'roast_chart.dart';

class RoastScreen extends StatelessWidget {
  const RoastScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<RoastController>();
    return Scaffold(
      drawer: _NavDrawer(controller: controller),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: ArtisanColors.title,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: Row(
          children: [
            const Text(
              'Artisan',
              style: TextStyle(color: ArtisanColors.title, fontWeight: FontWeight.w800, fontSize: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${controller.profile.title}  #${controller.batch}  ${controller.preset.name}',
                style: const TextStyle(color: ArtisanColors.axis, fontSize: 13, fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 980;
            return Column(
              children: [
                if (controller.alarmText != null || controller.message.isNotEmpty)
                  _MessageBar(controller: controller),
                Expanded(
                  child: wide
                      ? Row(
                          children: [
                            Expanded(child: _ChartFrame(controller: controller)),
                            SizedBox(width: 268, child: _Readout(controller: controller, vertical: true)),
                          ],
                        )
                      : Column(
                          children: [
                            Expanded(child: _ChartFrame(controller: controller)),
                            SizedBox(height: 108, child: _Readout(controller: controller, vertical: false)),
                          ],
                        ),
                ),
                _Controls(controller: controller),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ChartFrame extends StatelessWidget {
  const _ChartFrame({required this.controller});

  final RoastController controller;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: RoastChart(controller: controller)),
        Positioned(
          top: 8,
          right: 8,
          child: DecoratedBox(
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.88), borderRadius: BorderRadius.circular(4)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _LegendChip(label: 'ET', color: ArtisanColors.et, on: controller.showEt, onTap: () {
                  controller.showEt = !controller.showEt;
                  controller.changed();
                }),
                _LegendChip(label: 'BT', color: ArtisanColors.bt, on: controller.showBt, onTap: () {
                  controller.showBt = !controller.showBt;
                  controller.changed();
                }),
                _LegendChip(label: 'SV', color: ArtisanColors.sv, on: controller.showSv, onTap: () {
                  controller.showSv = !controller.showSv;
                  controller.changed();
                }),
                _LegendChip(label: 'ΔET', color: ArtisanColors.et, on: controller.showDeltaEt, onTap: () {
                  controller.showDeltaEt = !controller.showDeltaEt;
                  controller.changed();
                }),
                _LegendChip(label: 'ΔBT', color: ArtisanColors.bt, on: controller.showDeltaBt, onTap: () {
                  controller.showDeltaBt = !controller.showDeltaBt;
                  controller.changed();
                }),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.label, required this.color, required this.on, required this.onTap});

  final String label;
  final Color color;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(label, style: TextStyle(color: on ? color : Colors.grey, fontWeight: FontWeight.w800, fontSize: 12)),
      ),
    );
  }
}

class _NavDrawer extends StatelessWidget {
  const _NavDrawer({required this.controller});

  final RoastController controller;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final drawerWidth = width >= 980 ? 320.0 : (width * 0.82).clamp(260.0, 320.0);
    return Drawer(
      width: drawerWidth,
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Artisan',
                      style: TextStyle(
                        color: ArtisanColors.title,
                        fontWeight: FontWeight.w800,
                        fontSize: 24,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close, color: ArtisanColors.axis),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                '${controller.profile.title}\n#${controller.batch} · ${controller.preset.name}',
                style: const TextStyle(color: ArtisanColors.axis, fontSize: 13, height: 1.35),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _section('文件'),
                  _tile(context, Icons.folder_open, '打开曲线', controller.openProfile),
                  _tile(context, Icons.save_outlined, '保存', controller.saveProfile),
                  _tile(context, Icons.table_view_outlined, '导出 CSV', controller.exportCsv),
                  _tile(context, Icons.layers_outlined, '载入背景', () => controller.openProfile(backgroundOnly: true)),
                  _tile(context, Icons.copy_all_outlined, '当前曲线作背景', controller.useAsBackground),
                  _tile(context, Icons.layers_clear_outlined, '清除背景', controller.clearBackground),
                  if (controller.recent.isNotEmpty) ...[
                    _section('最近文件'),
                    for (final path in controller.recent.take(6))
                      _tile(
                        context,
                        Icons.history,
                        path.split('/').last,
                        () => controller.openRecent(path),
                      ),
                  ],
                  _section('烘焙'),
                  _tile(context, Icons.coffee_outlined, '烘焙属性', () => showPropertiesDialog(context, controller)),
                  _tile(context, Icons.notification_important_outlined, '报警', () => showAlarmDialog(context, controller)),
                  _tile(context, Icons.touch_app_outlined, '事件按钮', () => showButtonDialog(context, controller)),
                  _tile(context, Icons.rate_review_outlined, '杯测', () => showCuppingDialog(context, controller)),
                  _section('配置'),
                  _tile(context, Icons.bluetooth, '设备', () => showDeviceDialog(context, controller)),
                  _tile(context, Icons.tune, '采样与曲线', () => showSettingsDialog(context, controller)),
                  _tile(context, Icons.download_outlined, '加载 Kaleido 双系统配置', controller.loadBundledKaleidoAset),
                  _tile(context, Icons.upload_file_outlined, '导入 Artisan .aset…', controller.importAsetFile),
                  _section('工具'),
                  _tile(context, Icons.insights_outlined, '统计', () => showStatsDialog(context, controller)),
                  _tile(context, Icons.design_services_outlined, '曲线设计', () => showDesignerDialog(context, controller)),
                  _section('帮助'),
                  _tile(context, Icons.info_outline, '关于与设备范围', () => showScopeDialog(context)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Text(
        title,
        style: const TextStyle(
          color: ArtisanColors.title,
          fontWeight: FontWeight.w800,
          fontSize: 12,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, IconData icon, String label, VoidCallback action) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: ArtisanColors.button, size: 22),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      onTap: () {
        Navigator.of(context).maybePop();
        // Close drawer first, then run the action on the next frame.
        WidgetsBinding.instance.addPostFrameCallback((_) => action());
      },
    );
  }
}

class _MessageBar extends StatelessWidget {
  const _MessageBar({required this.controller});

  final RoastController controller;

  @override
  Widget build(BuildContext context) {
    final alarm = controller.alarmText;
    return Material(
      color: alarm == null ? const Color(0xFFF3F7FB) : const Color(0xFFFFF1F4),
      child: InkWell(
        onTap: alarm == null ? null : controller.dismissAlarm,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            alarm ?? controller.message,
            style: TextStyle(color: alarm == null ? ArtisanColors.title : ArtisanColors.selected, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class _Readout extends StatelessWidget {
  const _Readout({required this.controller, required this.vertical});

  final RoastController controller;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final samples = controller.profile.samples;
    final live = controller.monitoring;
    final et = live ? controller.live.et : (samples.isEmpty ? -1.0 : samples.last.et);
    final bt = live ? controller.live.bt : (samples.isEmpty ? -1.0 : samples.last.bt);
    final det = controller.etRor.isEmpty ? null : controller.etRor.last;
    final dbt = controller.btRor.isEmpty ? null : controller.btRor.last;
    final clock = controller.recording
        ? controller.clockSeconds
        : (samples.isEmpty ? 0.0 : samples.last.t);
    final charge = controller.profile.sampleAt(RoastProfile.charge);
    final shown = charge == null ? clock : clock - charge.t;
    final cells = [
      _Lcd(label: 'ET', value: _temp(et), background: ArtisanColors.et, foreground: Colors.white),
      _Lcd(label: 'BT', value: _temp(bt), background: ArtisanColors.bt, foreground: Colors.white),
      _Lcd(label: 'ΔET', value: _ror(det), background: ArtisanColors.deltaBackground, foreground: ArtisanColors.et),
      _Lcd(label: 'ΔBT', value: _ror(dbt), background: ArtisanColors.deltaBackground, foreground: ArtisanColors.bt),
      _Lcd(label: '时间', value: formatClock(shown < 0 ? 0 : shown), background: ArtisanColors.timerBackground, foreground: ArtisanColors.timerDigit),
    ];
    final phases = _Phases(controller: controller);
    final svPad = controller.preset.protocol == ProtocolKind.arduinoTc4 ||
            controller.preset.protocol == ProtocolKind.kaleido
        ? _SvPad(controller: controller)
        : null;
    if (!vertical) {
      return Row(
        children: [
          for (final cell in cells) Expanded(child: cell),
          if (svPad != null) Expanded(flex: 2, child: svPad),
          Expanded(flex: 2, child: phases),
        ],
      );
    }
    return ColoredBox(
      color: Colors.white,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        children: [
          ...cells,
          if (svPad != null) ...[
            const SizedBox(height: 8),
            svPad,
          ],
          const SizedBox(height: 8),
          phases,
          if (controller.preset.protocol.name == 'manual') _ManualPad(controller: controller),
          if (controller.live.weight != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('秤 ${controller.live.weight!.toStringAsFixed(1)} g', style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }

  String _temp(double value) {
    if (value <= 0 || value >= 900) return '---.-';
    return displayTemp(value, controller.mode).toStringAsFixed(1);
  }

  String _ror(double? value) {
    if (value == null) return '--.-';
    return displayRor(value, controller.mode).toStringAsFixed(1);
  }
}

class _Lcd extends StatelessWidget {
  const _Lcd({required this.label, required this.value, required this.background, required this.foreground});

  final String label;
  final String value;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ArtisanColors.axis)),
          DecoratedBox(
            decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(4)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(color: foreground, fontSize: 32, fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()], height: 1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Phases extends StatelessWidget {
  const _Phases({required this.controller});

  final RoastController controller;

  @override
  Widget build(BuildContext context) {
    final stats = controller.stats;
    final total = _liveTotal();
    String line(String name, double? seconds) {
      if (seconds == null || total == null || total <= 0) {
        return '$name  --:--';
      }
      return '$name  ${formatClock(seconds)}  ${(seconds / total * 100).toStringAsFixed(0)}%';
    }

    final dev = _liveDev();
    final dtr = (dev != null && total != null && total > 0) ? dev / total * 100 : stats.dtr;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(line('脱水', stats.dryTime), style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(line('美拉德', stats.maillardTime), style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(
          '发展  ${dev == null ? '--:--' : formatClock(dev)}  ${dtr == null ? '' : 'DTR ${dtr.toStringAsFixed(0)}%'}',
          style: const TextStyle(fontWeight: FontWeight.w700, color: ArtisanColors.bt),
        ),
        Text('AUC ${stats.auc == null ? '--' : stats.auc!.toStringAsFixed(0)}', style: const TextStyle(color: ArtisanColors.axis)),
      ],
    );
  }

  double? _liveTotal() {
    final charge = controller.profile.sampleAt(RoastProfile.charge);
    if (charge == null || controller.profile.samples.isEmpty) return controller.stats.roastTime;
    final end = controller.profile.sampleAt(RoastProfile.drop)?.t ?? controller.profile.samples.last.t;
    return end - charge.t;
  }

  double? _liveDev() {
    final fcs = controller.profile.sampleAt(RoastProfile.fcs);
    if (fcs == null || controller.profile.samples.isEmpty) return controller.stats.developmentTime;
    final end = controller.profile.sampleAt(RoastProfile.drop)?.t ?? controller.profile.samples.last.t;
    return end - fcs.t;
  }
}

class _SvPad extends StatelessWidget {
  const _SvPad({required this.controller});

  final RoastController controller;

  @override
  Widget build(BuildContext context) {
    final sv = controller.pidSv.clamp(controller.svMin, controller.svMax);
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            controller.followBackground ? 'SV（跟随背景）' : 'SV 目标豆温',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ArtisanColors.axis),
          ),
          Row(
            children: [
              FilledButton(
                style: artisanAction(background: ArtisanColors.sv, foreground: Colors.white),
                onPressed: () => controller.nudgePidSv(-1),
                child: const Text('-1'),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  sv.toStringAsFixed(0),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: ArtisanColors.sv,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              FilledButton(
                style: artisanAction(background: ArtisanColors.sv, foreground: Colors.white),
                onPressed: () => controller.nudgePidSv(1),
                child: const Text('+1'),
              ),
            ],
          ),
          Slider(
            value: sv.toDouble(),
            min: controller.svMin,
            max: controller.svMax,
            onChanged: (value) => controller.setPidSv(value, send: false),
            onChangeEnd: (value) => controller.setPidSv(value),
          ),
        ],
      ),
    );
  }
}

class _ManualPad extends StatelessWidget {
  const _ManualPad({required this.controller});

  final RoastController controller;

  @override
  Widget build(BuildContext context) {
    Widget row(String label, double value, void Function(double) apply) {
      return Row(
        children: [
          SizedBox(width: 28, child: Text(label)),
          IconButton(onPressed: () => apply(value - 1), icon: const Icon(Icons.remove)),
          Text(displayTemp(value, controller.mode).toStringAsFixed(1)),
          IconButton(onPressed: () => apply(value + 1), icon: const Icon(Icons.add)),
        ],
      );
    }

    return Column(
      children: [
        row('ET', controller.manualEt, (value) => controller.setManual(toCelsius(displayTemp(value, controller.mode), controller.mode), null)),
        row('BT', controller.manualBt, (value) => controller.setManual(null, toCelsius(displayTemp(value, controller.mode), controller.mode))),
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.controller});

  final RoastController controller;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: Column(
          children: [
            Row(
              children: [
                FilledButton(
                  style: artisanAction(
                    background: Colors.white,
                    foreground: controller.monitoring ? ArtisanColors.offText : ArtisanColors.onText,
                  ),
                  onPressed: controller.togglePower,
                  child: Text(controller.monitoring ? 'OFF' : 'ON'),
                ),
                const SizedBox(width: 6),
                FilledButton(
                  style: artisanAction(
                    background: Colors.white,
                    foreground: controller.recording ? ArtisanColors.offText : ArtisanColors.onText,
                  ),
                  onPressed: controller.toggleRecord,
                  child: Text(controller.recording ? 'STOP' : 'START'),
                ),
                const SizedBox(width: 6),
                FilledButton(
                  style: artisanAction(background: Colors.white, foreground: ArtisanColors.button),
                  onPressed: controller.resetCurve,
                  child: const Text('RESET'),
                ),
                if (controller.monitoring && controller.canSwapEtBt) ...[
                  const SizedBox(width: 10),
                  FilterChip(
                    label: Text(controller.device.swapEtBt ? 'ET⇄BT' : 'ET/BT'),
                    selected: controller.device.swapEtBt,
                    onSelected: controller.setSwapEtBt,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
                const Spacer(),
                Text(controller.session.status, style: const TextStyle(color: ArtisanColors.axis)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _mark(0, 'CHARGE'),
                _mark(1, 'DRY END'),
                _mark(2, 'FCs'),
                _mark(3, 'FCe'),
                _mark(4, 'SCs'),
                _mark(5, 'SCe'),
                _mark(6, 'DROP'),
                _mark(7, 'COOL END'),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final button in controller.buttons)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilledButton(
                        style: artisanAction(
                          background: ArtisanColors.eventColors[button.type.clamp(0, 3).toInt()],
                          foreground: Colors.white,
                        ),
                        onPressed: () => controller.pressButton(button),
                        child: Text(button.label),
                      ),
                    ),
                ],
              ),
            ),
            Row(
              children: [
                for (var i = 0; i < 4; i++)
                  if (i >= controller.sliderVisibility.length || controller.sliderVisibility[i])
                    Expanded(
                      child: Column(
                        children: [
                          Text('${controller.eventLabels[i]} ${controller.sliders[i].round()}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                          Slider(
                            value: controller.sliders[i],
                            max: 100,
                            onChanged: (value) => controller.setSlider(i, value),
                            onChangeEnd: (value) => controller.setSlider(i, value, commit: true),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _mark(int index, String label) {
    final marked = controller.profile.timeindex[index] >= 0;
    final sample = controller.profile.sampleAt(index);
    final charge = controller.profile.sampleAt(RoastProfile.charge);
    String? time;
    if (sample != null) {
      time = formatClock(charge == null ? sample.t : sample.t - charge.t);
    }
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: FilledButton(
          style: artisanAction(
            background: marked ? ArtisanColors.selected : ArtisanColors.button,
            foreground: Colors.white,
          ),
          onPressed: () => controller.mark(index),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: const TextStyle(fontSize: 12)),
              if (time != null) Text(time, style: const TextStyle(fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }
}
