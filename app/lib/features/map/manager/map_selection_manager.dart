import 'package:flutter/foundation.dart';

import '../model/selected_map_target.dart';

class MapSelectionManager extends ChangeNotifier {
  SelectedMapTarget? _selectedTarget;
  bool _isQuerying = false;
  String? _message;

  SelectedMapTarget? get selectedTarget => _selectedTarget;
  bool get isQuerying => _isQuerying;
  String? get message => _message;

  void beginQuery() {
    _isQuerying = true;
    _message = null;
    notifyListeners();
  }

  void selectTarget(SelectedMapTarget target) {
    _selectedTarget = target;
    _isQuerying = false;
    _message = null;
    notifyListeners();
  }

  void setMessage(String message) {
    _message = message;
    _isQuerying = false;
    notifyListeners();
  }

  void clear() {
    _selectedTarget = null;
    _isQuerying = false;
    _message = null;
    notifyListeners();
  }
}
