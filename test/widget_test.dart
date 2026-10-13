import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:artisan_flutter/main.dart';
import 'package:artisan_flutter/state/roast_controller.dart';

void main() {
  testWidgets('tablet roast screen records a simulated curve', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = RoastController();
    await tester.pumpWidget(ArtisanApp(controller: controller));
    expect(find.text('CHARGE'), findsOneWidget);
    expect(find.text('ON'), findsOneWidget);

    await tester.tap(find.text('ON'));
    await tester.pump();
    await tester.tap(find.text('START'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('STOP'), findsOneWidget);
    expect(controller.profile.samples.length, greaterThan(0));
    expect(controller.profile.samples.last.bt, greaterThan(50));

    await tester.tap(find.text('CHARGE'));
    await tester.pump();
    expect(controller.profile.timeindex[0], greaterThanOrEqualTo(0));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
