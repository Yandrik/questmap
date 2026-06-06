import 'package:flutter/foundation.dart';

enum MapInteractionMode {
  browse,
  selectStart,
  selectEnd,
  selectPoint,
  drawArea,
}

class MapInteractionManager extends ChangeNotifier {
  MapInteractionMode _mode = MapInteractionMode.browse;

  MapInteractionMode get mode => _mode;

  void setMode(MapInteractionMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
  }
}
