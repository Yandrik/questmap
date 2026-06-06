import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../app/app_config.dart';

Future<void> configureTileHttpHeaders() async {
  if (kIsWeb ||
      (defaultTargetPlatform != TargetPlatform.android &&
          defaultTargetPlatform != TargetPlatform.iOS)) {
    return;
  }

  await setHttpHeaders({'User-Agent': tileUserAgent});
}
