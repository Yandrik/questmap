import 'package:flutter/widgets.dart';

import '../_shared/services/tile_http_header_service.dart';
import 'meander.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureTileHttpHeaders();
  runApp(const MeanderApp());
}
