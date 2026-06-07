import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:material_duration_picker/material_duration_picker.dart';

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
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalMaterialDurationPickerLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      home: const MapShell(),
    );
  }
}
