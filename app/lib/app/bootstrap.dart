import 'package:flutter/widgets.dart';

import '../_shared/services/tile_http_header_service.dart';
import '../locator.dart';
import 'meander.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureDependencies();
  await configureTileHttpHeaders();
  runApp(const MeanderApp());
}
