import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:artisan_flutter/core/aset_codec.dart';
import 'package:artisan_flutter/core/curve_math.dart';
import 'package:artisan_flutter/core/profile_codec.dart';
import 'package:artisan_flutter/devices/protocols.dart';
import 'package:artisan_flutter/models/roast_models.dart';

void main() {
  test('modbus crc matches the standard request frame', () {
    final crc = modbusCrc([0x01, 0x03, 0x00, 0x00, 0x00, 0x0A]);
    expect(crc & 0xFF, 0xC5);
    expect((crc >> 8) & 0xFF, 0xCD);
  });

  test('santoker frame round trip keeps bean temperature', () {
    final protocol = SantokerProtocol();
    final frame = protocol.frame(0xF3, 1984);
    protocol.addBytes(frame);
    expect(protocol.reading.bt, closeTo(198.4, 0.01));
  });

  test('center 309 splits channel one and two', () {
    final frame = List<int>.filled(45, 0);
    frame[0] = 0x02;
    frame[1] = 0x80;
    frame[7] = 0x07;
    frame[8] = 0xD0;
    frame[9] = 0x03;
    frame[10] = 0xE8;
    final protocol = Center309Protocol();
    protocol.addBytes(frame);
    expect(protocol.reading.et, closeTo(200, 0.01));
    expect(protocol.reading.bt, closeTo(100, 0.01));
  });

  test('kaleido text updates both temperatures', () {
    final protocol = KaleidoProtocol();
    protocol.addText('{1,BT:150.5,ET:190}\n');
    expect(protocol.reading.bt, 150.5);
    expect(protocol.reading.et, 190);
  });

  test('arduino tc4 read parses et bt heater fan sv', () {
    final protocol = ArduinoTc4Protocol(etChannel: '2', btChannel: '1');
    protocol.addText('#\n'); // CHAN ack
    protocol.addText('#\n'); // UNITS ack
    protocol.addText('#\n'); // FILT ack
    protocol.addText('37.9,195.5,168.2,70,40,180\n');
    expect(protocol.reading.et, closeTo(195.5, 0.01));
    expect(protocol.reading.bt, closeTo(168.2, 0.01));
    expect(protocol.reading.power, 70);
    expect(protocol.reading.fan, 40);
    expect(protocol.reading.setpoint, 180);
  });

  test('kaleido dual-system aset maps to tc4 preset', () {
    final path = File('../m10/Kaleido_双系统.aset').existsSync()
        ? '../m10/Kaleido_双系统.aset'
        : 'assets/settings/Kaleido_双系统.aset';
    final raw = File(path).readAsStringSync();
    final config = decodeArtisanAset(raw);
    expect(config.presetId, 'kaleido-tc4');
    expect(config.etChannel, '2');
    expect(config.btChannel, '1');
    expect(config.interval, closeTo(1.5, 0.01));
    expect(config.mode, 'C');
    expect(config.eventLabels[1], '滚筒');
    expect(config.eventLabels[2], '风门');
    expect(config.eventLabels[3], '火力');
    expect(config.sliderCommands[1], 'IO3,{}');
    expect(config.sliderCommands[2], 'OT2,{}');
    expect(config.sliderCommands[3], 'OT1,{}');
    expect(config.buttons.any((b) => b.label.contains('火力') && b.command.contains('OT1')), isTrue);
    expect(config.buttons.any((b) => b.command == 'CLDN,ON'), isTrue);
    expect(config.buttons.any((b) => b.command == 'PIDon'), isTrue);
    expect(config.device.remoteName, 'Kaleido_M');
    expect(config.svMin, 50);
    expect(config.svMax, 230);
    expect(config.sliderVisibility.every((v) => !v), isTrue);
  });

  test('artisan alog keeps the curve and charge index', () {
    const raw = "{'title': 'Yirga', 'beans': 'Guji', 'mode': 'C', "
        "'timex': [0, 1, 2], 'temp1': [180, 185, 190], 'temp2': [90, 95, 100], "
        "'timeindex': [0, -1, -1, -1, -1, -1, 2, -1], "
        "'weight': ('g', 250, 210)}";
    final profile = decodeArtisanAlog(raw);
    expect(profile.title, 'Yirga');
    expect(profile.samples, hasLength(3));
    expect(profile.samples[2].bt, 100);
    expect(profile.timeindex[RoastProfile.charge], 0);
    expect(profile.weightIn, 250);
    expect(profile.weightOut, 210);
  });

  test('rate of rise is degrees per minute', () {
    final samples = [
      const Sample(t: 0, et: 100, bt: 100),
      const Sample(t: 30, et: 110, bt: 105),
      const Sample(t: 60, et: 120, bt: 112),
    ];
    final ror = rateOfRise(samples, true, spanSeconds: 30, smooth: 1);
    expect(ror.last, closeTo(14, 0.01));
  });

  test('development ratio uses drop minus first crack', () {
    final profile = RoastProfile(
      samples: const [
        Sample(t: 0, et: 180, bt: 90),
        Sample(t: 60, et: 190, bt: 150),
        Sample(t: 120, et: 200, bt: 180),
        Sample(t: 180, et: 210, bt: 200),
      ],
      timeindex: [0, 1, 2, -1, -1, -1, 3, -1],
    );
    final stats = computeStats(profile, aucBase: 0);
    expect(stats.roastTime, 180);
    expect(stats.developmentTime, 60);
    expect(stats.dtr, closeTo(100 * 60 / 180, 0.01));
  });
}
