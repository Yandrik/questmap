import 'package:flutter/material.dart';

import '../features/map/pages/map_shell.dart';
import 'app_config.dart';
import 'app_theme.dart';

class MeanderApp extends StatelessWidget {
  const MeanderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appTitle,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const MapShell(),
    );
  }
}
