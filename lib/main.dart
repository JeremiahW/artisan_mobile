import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/roast_controller.dart';
import 'theme/artisan_theme.dart';
import 'ui/roast_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = RoastController();
  await controller.load();
  runApp(ArtisanApp(controller: controller));
}

class ArtisanApp extends StatelessWidget {
  const ArtisanApp({super.key, required this.controller});

  final RoastController controller;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<RoastController>.value(
      value: controller,
      child: MaterialApp(
        title: 'Artisan',
        debugShowCheckedModeBanner: false,
        theme: artisanTheme(),
        home: const RoastScreen(),
      ),
    );
  }
}
