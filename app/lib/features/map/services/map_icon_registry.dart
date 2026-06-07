import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_svg/flutter_svg.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'map_icon_catalog.dart';

class MapIconRegistry {
  const MapIconRegistry();

  Future<void> registerStyleIcons(MapLibreMapController controller) async {
    for (final entry in MapIconCatalog.styleIcons.entries) {
      final imageBytes = await _svgToPng(entry.value);
      await controller.addImage(entry.key, imageBytes, true);
    }
  }

  Future<Uint8List> _svgToPng(String svg, {int size = 48}) async {
    final pictureInfo = await vg.loadPicture(
      SvgStringLoader(svg.replaceAll('currentColor', '#000000')),
      null,
    );

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final sourceSize = pictureInfo.size;
    final scale =
        size /
        math.max(
          sourceSize.width == 0 ? size.toDouble() : sourceSize.width,
          sourceSize.height == 0 ? size.toDouble() : sourceSize.height,
        );
    final dx = (size - sourceSize.width * scale) / 2;
    final dy = (size - sourceSize.height * scale) / 2;

    canvas
      ..translate(dx, dy)
      ..scale(scale);
    canvas.drawPicture(pictureInfo.picture);

    final rasterPicture = recorder.endRecording();
    final image = await rasterPicture.toImage(size, size);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    pictureInfo.picture.dispose();
    rasterPicture.dispose();
    image.dispose();

    if (byteData == null) {
      throw StateError('Unable to rasterize Iconify SVG for MapLibre.');
    }

    return byteData.buffer.asUint8List();
  }
}
