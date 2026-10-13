import 'dart:io';

import 'package:flutter/material.dart';

import '../devices/device_catalog.dart';
import '../devices/spp_helpers.dart';
import '../models/roast_models.dart';
import '../state/roast_controller.dart';
import '../theme/artisan_theme.dart';

Future<void> showDeviceDialog(BuildContext context, RoastController controller) {
  return showDialog<void>(
    context: context,
    builder: (context) => _DeviceDialog(controller: controller),
  );
}

class _DeviceDialog extends StatefulWidget {
  const _DeviceDialog({required this.controller});

  final RoastController controller;

  @override
  State<_DeviceDialog> createState() => _DeviceDialogState();
}

class _DeviceDialogState extends State<_DeviceDialog> {
  late final TextEditingController host;
  late final TextEditingController port;
  late final TextEditingController slave;
  late final TextEditingController address;
  late final TextEditingController scale;
  late final TextEditingController mac;
  late final TextEditingController macName;

  @override
  void initState() {
    super.initState();
    final device = widget.controller.device;
    host = TextEditingController(text: device.host);
    port = TextEditingController(text: '${device.port}');
    slave = TextEditingController(text: '${device.slave}');
    address = TextEditingController(text: '${device.address}');
    scale = TextEditingController(text: '${device.scale}');
    mac = TextEditingController(text: device.remoteId);
    macName = TextEditingController(
      text: device.remoteName.isEmpty ? 'Kaleido_M' : device.remoteName,
    );
  }

  @override
  void dispose() {
    host.dispose();
    port.dispose();
    slave.dispose();
    address.dispose();
    scale.dispose();
    mac.dispose();
    macName.dispose();
    super.dispose();
  }

  void _apply() {
    final device = widget.controller.device;
    device.host = host.text.trim();
    device.port = int.tryParse(port.text) ?? device.port;
    device.slave = int.tryParse(slave.text) ?? device.slave;
    device.address = int.tryParse(address.text) ?? device.address;
    device.scale = double.tryParse(scale.text) ?? device.scale;
    widget.controller.changed();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final preset = controller.preset;
    return AlertDialog(
      title: const Text('设备'),
      content: SizedBox(
        width: 640,
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            return ListView(
              shrinkWrap: true,
              children: [
                DropdownButton<String>(
                  isExpanded: true,
                  value: preset.id,
                  items: [
                    for (final item in devicePresets)
                      DropdownMenuItem(value: item.id, child: Text('${item.group} · ${item.name}')),
                  ],
                  onChanged: (id) {
                    if (id == null) return;
                    controller.selectPreset(id);
                    setState(() {});
                  },
                ),
                const SizedBox(height: 8),
                Text(preset.detail),
                const SizedBox(height: 8),
                if (preset.transport == TransportKind.spp && !Platform.isAndroid)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      '当前是 iPad。HC-05 / Kaleido_M 这类需要配对码的经典蓝牙串口，第三方 App 无法在 iOS 上连接。请改用 Android 平板。',
                      style: TextStyle(color: ArtisanColors.selected, fontWeight: FontWeight.w600),
                    ),
                  ),
                if (preset.transport == TransportKind.spp && Platform.isAndroid)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      '扫描前请：打开系统蓝牙；允许「附近的设备」和「位置」；打开定位服务。'
                      'Kaleido 双系统请配对「Kaleido_M」；触摸屏需点「允许」。'
                      '扫描列表会把 Kaleido_M 等设备排在前面。',
                      style: TextStyle(color: ArtisanColors.title, fontWeight: FontWeight.w600),
                    ),
                  ),
                Text(excludedDeviceNote, style: const TextStyle(color: ArtisanColors.axis)),
                if (preset.transport == TransportKind.websocket) ...[
                  TextField(controller: host, decoration: const InputDecoration(labelText: '主机')),
                  TextField(controller: port, decoration: const InputDecoration(labelText: '端口'), keyboardType: TextInputType.number),
                ],
                if (preset.protocol == ProtocolKind.modbusRtu) ...[
                  TextField(controller: slave, decoration: const InputDecoration(labelText: '从站'), keyboardType: TextInputType.number),
                  TextField(controller: address, decoration: const InputDecoration(labelText: '起始寄存器'), keyboardType: TextInputType.number),
                  DropdownButton<int>(
                    value: controller.device.function,
                    items: const [
                      DropdownMenuItem(value: 3, child: Text('功能 03 保持寄存器')),
                      DropdownMenuItem(value: 4, child: Text('功能 04 输入寄存器')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      controller.device.function = value;
                      controller.changed();
                      setState(() {});
                    },
                  ),
                  TextField(controller: scale, decoration: const InputDecoration(labelText: '除数，原始值 / 除数 = °C'), keyboardType: TextInputType.number),
                ],
                if (controller.canSwapEtBt)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('交换 ET / BT'),
                    subtitle: Text(
                      controller.device.swapEtBt
                          ? '当前：第一路 → BT，第二路 → ET'
                          : '当前：第一路 → ET，第二路 → BT',
                    ),
                    value: controller.device.swapEtBt,
                    onChanged: (value) {
                      controller.setSwapEtBt(value);
                      setState(() {});
                    },
                  ),
                if (preset.transport == TransportKind.ble || preset.transport == TransportKind.spp) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilledButton(
                        onPressed: controller.scanning
                            ? null
                            : () async {
                                _apply();
                                await controller.scan();
                                if (mounted) setState(() {});
                              },
                        child: Text(controller.scanning ? '扫描中…' : '扫描'),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          controller.device.remoteName.isEmpty
                              ? '未选择'
                              : '${controller.device.remoteName}\n${controller.device.remoteId}',
                        ),
                      ),
                    ],
                  ),
                  if (controller.message.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(controller.message, style: const TextStyle(fontSize: 12)),
                    ),
                  for (final item in controller.found)
                    ListTile(
                      dense: true,
                      title: Text(item.name.isEmpty ? item.id : item.name),
                      subtitle: Text(
                        [
                          item.id,
                          if (item.bonded) '已配对',
                          if (looksLikeClassicSppName(item.name))
                            '配对码 ${pinFromDeviceName(item.name) ?? "见设备名"}',
                        ].join(' · '),
                      ),
                      selected: item.id.toUpperCase() == controller.device.remoteId.toUpperCase(),
                      onTap: () {
                        controller.chooseDevice(item);
                        mac.text = item.id;
                        macName.text = item.name;
                        setState(() {});
                      },
                    ),
                  if (preset.transport == TransportKind.spp && Platform.isAndroid) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: macName,
                      decoration: const InputDecoration(
                        labelText: '手动设备名（可选）',
                        hintText: 'Kaleido_M',
                      ),
                    ),
                    TextField(
                      controller: mac,
                      decoration: const InputDecoration(
                        labelText: '手动 MAC 地址',
                        hintText: 'AA:BB:CC:DD:EE:FF',
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () {
                          controller.setManualAddress(mac.text, name: macName.text);
                          setState(() {});
                        },
                        child: const Text('使用此 MAC'),
                      ),
                    ),
                  ],
                ],
                if (controller.session.log.isNotEmpty) ...[
                  const Divider(),
                  const Text('通信', style: TextStyle(fontWeight: FontWeight.w700)),
                  for (final line in controller.session.log.reversed.take(8)) Text(line, style: const TextStyle(fontSize: 12)),
                ],
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            _apply();
            Navigator.pop(context);
          },
          child: const Text('完成'),
        ),
      ],
    );
  }
}

Future<void> showPropertiesDialog(BuildContext context, RoastController controller) {
  final profile = controller.profile;
  final title = TextEditingController(text: profile.title);
  final beans = TextEditingController(text: profile.beans);
  final person = TextEditingController(text: profile.operatorName);
  final machine = TextEditingController(text: profile.machine);
  final notes = TextEditingController(text: profile.notes);
  final weightIn = TextEditingController(text: profile.weightIn == 0 ? '' : profile.weightIn.toString());
  final weightOut = TextEditingController(text: profile.weightOut == 0 ? '' : profile.weightOut.toString());
  final moisture = TextEditingController(text: profile.moisture == 0 ? '' : profile.moisture.toString());
  final color = TextEditingController(text: profile.color == 0 ? '' : profile.color.toString());
  final future = showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('烘焙属性'),
      content: SizedBox(
        width: 520,
        child: ListView(
          shrinkWrap: true,
          children: [
            TextField(controller: title, decoration: const InputDecoration(labelText: '标题')),
            TextField(controller: beans, decoration: const InputDecoration(labelText: '豆子')),
            TextField(controller: person, decoration: const InputDecoration(labelText: '操作者')),
            TextField(controller: machine, decoration: const InputDecoration(labelText: '烘焙机')),
            TextField(controller: weightIn, decoration: const InputDecoration(labelText: '入豆重 g'), keyboardType: TextInputType.number),
            TextField(controller: weightOut, decoration: const InputDecoration(labelText: '出豆重 g'), keyboardType: TextInputType.number),
            TextField(controller: moisture, decoration: const InputDecoration(labelText: '水分 %'), keyboardType: TextInputType.number),
            TextField(controller: color, decoration: const InputDecoration(labelText: '色值'), keyboardType: TextInputType.number),
            TextField(controller: notes, decoration: const InputDecoration(labelText: '备注'), maxLines: 3),
            Row(
              children: [
                TextButton(onPressed: controller.tareScale, child: const Text('秤去皮')),
                TextButton(onPressed: () => controller.captureWeight(true), child: const Text('记入豆重')),
                TextButton(onPressed: () => controller.captureWeight(false), child: const Text('记出豆重')),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            profile
              ..title = title.text.trim().isEmpty ? '未命名' : title.text.trim()
              ..beans = beans.text.trim()
              ..operatorName = person.text.trim()
              ..machine = machine.text.trim()
              ..notes = notes.text.trim()
              ..weightIn = double.tryParse(weightIn.text) ?? 0
              ..weightOut = double.tryParse(weightOut.text) ?? 0
              ..moisture = double.tryParse(moisture.text) ?? 0
              ..color = int.tryParse(color.text) ?? 0;
            controller.changed();
            Navigator.pop(context);
          },
          child: const Text('保存'),
        ),
      ],
    ),
  );
  future.whenComplete(() {
    title.dispose();
    beans.dispose();
    person.dispose();
    machine.dispose();
    notes.dispose();
    weightIn.dispose();
    weightOut.dispose();
    moisture.dispose();
    color.dispose();
  });
  return future;
}

Future<void> showSettingsDialog(BuildContext context, RoastController controller) {
  return showDialog<void>(
    context: context,
    builder: (context) => _SettingsDialog(controller: controller),
  );
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.controller});

  final RoastController controller;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late final TextEditingController span;
  late final TextEditingController smooth;
  late final TextEditingController interval;
  late final TextEditingController target;
  late final TextEditingController auc;
  late final TextEditingController dry;
  late final TextEditingController fcs;
  late final TextEditingController sv;
  late final TextEditingController kp;
  late final TextEditingController ki;
  late final TextEditingController kd;

  @override
  void initState() {
    super.initState();
    final c = widget.controller;
    span = TextEditingController(text: c.rorSpan.toString());
    smooth = TextEditingController(text: '${c.smooth}');
    interval = TextEditingController(text: c.interval.toString());
    target = TextEditingController(text: c.targetTemp.toString());
    auc = TextEditingController(text: c.aucBase.toString());
    dry = TextEditingController(text: c.dryTemp.toString());
    fcs = TextEditingController(text: c.fcsTemp.toString());
    sv = TextEditingController(text: c.pidSv.toString());
    kp = TextEditingController(text: c.kp.toString());
    ki = TextEditingController(text: c.ki.toString());
    kd = TextEditingController(text: c.kd.toString());
  }

  @override
  void dispose() {
    for (final item in [span, smooth, interval, target, auc, dry, fcs, sv, kp, ki, kd]) {
      item.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return AlertDialog(
      title: const Text('采样与曲线'),
      content: SizedBox(
        width: 480,
        child: ListView(
          shrinkWrap: true,
          children: [
            DropdownButton<String>(
              value: controller.mode,
              items: const [
                DropdownMenuItem(value: 'C', child: Text('摄氏 °C')),
                DropdownMenuItem(value: 'F', child: Text('华氏 °F')),
              ],
              onChanged: (value) {
                if (value == null) return;
                controller.mode = value;
                controller.profile.mode = value;
                setState(() {});
              },
            ),
            TextField(controller: interval, decoration: const InputDecoration(labelText: '采样间隔（秒）')),
            TextField(controller: span, decoration: const InputDecoration(labelText: '升温率窗口（秒）')),
            TextField(controller: smooth, decoration: const InputDecoration(labelText: '升温率平滑点数')),
            TextField(controller: target, decoration: const InputDecoration(labelText: '预测目标豆温 °C')),
            TextField(controller: auc, decoration: const InputDecoration(labelText: 'AUC 基准温度 °C')),
            TextField(controller: dry, decoration: const InputDecoration(labelText: '未标记时的脱水温度 °C')),
            TextField(controller: fcs, decoration: const InputDecoration(labelText: '未标记时的一爆温度 °C')),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('背景按 CHARGE 对齐'),
              value: controller.alignBackground,
              onChanged: (value) => setState(() => controller.alignBackground = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('按时间重放背景事件'),
              value: controller.replayEvents,
              onChanged: (value) => setState(() => controller.replayEvents = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('PID 控制火力'),
              value: controller.pidOn,
              onChanged: (value) {
                controller.pidOn = value;
                controller.session.command(value ? 'pidOn' : 'pidOff', 0);
                setState(() {});
              },
            ),
            TextField(controller: sv, decoration: const InputDecoration(labelText: 'PID 目标豆温 °C')),
            TextField(controller: kp, decoration: const InputDecoration(labelText: 'P')),
            TextField(controller: ki, decoration: const InputDecoration(labelText: 'I')),
            TextField(controller: kd, decoration: const InputDecoration(labelText: 'D')),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            controller
              ..interval = double.tryParse(interval.text) ?? controller.interval
              ..rorSpan = double.tryParse(span.text) ?? controller.rorSpan
              ..smooth = int.tryParse(smooth.text) ?? controller.smooth
              ..targetTemp = double.tryParse(target.text) ?? controller.targetTemp
              ..aucBase = double.tryParse(auc.text) ?? controller.aucBase
              ..dryTemp = double.tryParse(dry.text) ?? controller.dryTemp
              ..fcsTemp = double.tryParse(fcs.text) ?? controller.fcsTemp
              ..pidSv = double.tryParse(sv.text) ?? controller.pidSv
              ..kp = double.tryParse(kp.text) ?? controller.kp
              ..ki = double.tryParse(ki.text) ?? controller.ki
              ..kd = double.tryParse(kd.text) ?? controller.kd;
            controller.changed();
            Navigator.pop(context);
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

Future<void> showAlarmDialog(BuildContext context, RoastController controller) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('报警'),
      content: SizedBox(
        width: 560,
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => ListView(
            shrinkWrap: true,
            children: [
              for (final alarm in controller.alarms)
                SwitchListTile(
                  title: Text(alarm.description.isEmpty ? alarm.source.name : alarm.description),
                  subtitle: Text('${alarm.source.name} ${alarm.compare == AlarmCompare.above ? '>' : '<'} ${alarm.threshold}'),
                  value: alarm.enabled,
                  onChanged: (value) {
                    alarm.enabled = value;
                    alarm.fired = false;
                    controller.changed();
                  },
                ),
              TextButton(
                onPressed: () {
                  controller.alarms.add(AlarmRule(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    description: '新报警',
                  ));
                  controller.changed();
                },
                child: const Text('添加豆温报警'),
              ),
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
    ),
  );
}

Future<void> showButtonDialog(BuildContext context, RoastController controller) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('事件按钮'),
      content: SizedBox(
        width: 520,
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => ListView(
            shrinkWrap: true,
            children: [
              for (var i = 0; i < controller.buttons.length; i++)
                ListTile(
                  title: Text(controller.buttons[i].label),
                  subtitle: Text('${controller.eventLabels[controller.buttons[i].type.clamp(0, 3).toInt()]} ${controller.buttons[i].value.round()}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      controller.buttons.removeAt(i);
                      controller.changed();
                    },
                  ),
                ),
              TextButton(
                onPressed: () {
                  controller.buttons.add(EventButton(label: '新按钮', type: 2, value: 50));
                  controller.changed();
                },
                child: const Text('添加按钮'),
              ),
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
    ),
  );
}

Future<void> showStatsDialog(BuildContext context, RoastController controller) {
  final stats = controller.stats;
  final profile = controller.profile;
  String t(double? value) => value == null ? '--' : formatClock(value);
  String temp(double? value) => value == null ? '--' : '${displayTemp(value, controller.mode).toStringAsFixed(1)}°';
  final report = '''
${profile.title}
豆子 ${profile.beans}
烘焙机 ${profile.machine}
入豆 ${profile.weightIn} g    出豆 ${profile.weightOut} g    失重 ${stats.weightLoss == null ? '--' : '${stats.weightLoss!.toStringAsFixed(1)}%'}

CHARGE ${temp(stats.chargeBt)}
TP ${t(stats.tpFromCharge)}  ${temp(stats.tpBt)}
DRY ${t(stats.dryTime)}  ${temp(stats.dryBt)}
FCs ${temp(stats.fcsBt)}
DROP ${t(stats.roastTime)}  ${temp(stats.dropBt)}

脱水 ${t(stats.dryTime)}
美拉德 ${t(stats.maillardTime)}
发展 ${t(stats.developmentTime)}
DTR ${stats.dtr == null ? '--' : '${stats.dtr!.toStringAsFixed(1)}%'}
AUC ${stats.auc == null ? '--' : stats.auc!.toStringAsFixed(1)} °C·min
''';
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('统计'),
      content: SizedBox(width: 420, child: SelectableText(report)),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
    ),
  );
}

Future<void> showCuppingDialog(BuildContext context, RoastController controller) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('杯测'),
      content: SizedBox(
        width: 480,
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => ListView(
            shrinkWrap: true,
            children: [
              for (var i = 0; i < flavorLabels.length; i++)
                Row(
                  children: [
                    SizedBox(width: 72, child: Text(flavorLabels[i])),
                    Expanded(
                      child: Slider(
                        min: 0,
                        max: 10,
                        divisions: 20,
                        value: controller.profile.flavors[i],
                        label: controller.profile.flavors[i].toStringAsFixed(1),
                        onChanged: (value) {
                          controller.profile.flavors[i] = value;
                          controller.changed();
                        },
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
    ),
  );
}

Future<void> showDesignerDialog(BuildContext context, RoastController controller) async {
  final points = <(double, double)>[
    (0, 90),
    (4, 150),
    (8, 185),
    (11, 205),
  ];
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('曲线设计'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('用时间和豆温描一条目标曲线，放到背景上对照。'),
              for (var i = 0; i < points.length; i++)
                Text('${points[i].$1.toStringAsFixed(1)} min    ${points[i].$2.toStringAsFixed(0)} °C'),
              TextButton(
                onPressed: () {
                  final last = points.last;
                  setState(() => points.add((last.$1 + 1, last.$2 + 5)));
                },
                child: const Text('加一个点'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              points.sort((a, b) => a.$1.compareTo(b.$1));
              final samples = <Sample>[];
              for (var i = 0; i < points.length - 1; i++) {
                final a = points[i];
                final b = points[i + 1];
                final steps = ((b.$1 - a.$1) * 60).round().clamp(1, 3600);
                for (var s = 0; s < steps; s++) {
                  final u = s / steps;
                  samples.add(Sample(
                    t: (a.$1 + (b.$1 - a.$1) * u) * 60,
                    et: -1,
                    bt: a.$2 + (b.$2 - a.$2) * u,
                  ));
                }
              }
              samples.add(Sample(t: points.last.$1 * 60, et: -1, bt: points.last.$2));
              controller.applyDesigner(samples);
              Navigator.pop(context);
            },
            child: const Text('放到背景'),
          ),
        ],
      ),
    ),
  );
}

Future<void> showScopeDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const AlertDialog(
      title: Text('Artisan'),
      content: SizedBox(
        width: 480,
        child: Text(
          '这是桌面版 Artisan 的平板界面，第一阶段面向 Android 平板。\n\n'
          '可以记录风温和豆温、升温率、CHARGE 到 COOL 的阶段、事件按钮和滑条、报警、PID、背景曲线、杯测和统计。\n\n'
          '蓝牙支持 Santoker、BlueDOT、IKAWA 和 Acaia。蓝牙串口支持 CENTER、MODBUS RTU、Santoker 帧、Kaleido 文本、Kaleido 双系统 (TC4) 和 ASCII 双通道。Kaleido 也可以走 Wi-Fi。\n\n'
          '可用「配置 → 加载 Kaleido 双系统配置」导入 m10/Kaleido_双系统.aset。\n\n'
          'Phidget、Yoctopuce 和 Aillio Bullet 需要桌面 USB 驱动，这一版不连接。iPad 会在下一阶段沿用同一套蓝牙代码。',
        ),
      ),
    ),
  );
}
