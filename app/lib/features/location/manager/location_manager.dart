import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../_shared/models/geo_coordinate.dart';

class LocationManager extends ChangeNotifier {
  PermissionStatus? _permissionStatus;
  GeoCoordinate? _lastUserLocation;
  bool _isRequesting = false;
  bool _isUserLocationEnabled = false;
  bool _hasCenteredOnUserLocation = false;
  String? _message;

  PermissionStatus? get permissionStatus => _permissionStatus;
  GeoCoordinate? get lastUserLocation => _lastUserLocation;
  bool get isRequesting => _isRequesting;
  bool get isUserLocationEnabled => _isUserLocationEnabled;
  bool get hasCenteredOnUserLocation => _hasCenteredOnUserLocation;
  String? get message => _message;

  bool get isPermanentlyDenied =>
      _permissionStatus?.isPermanentlyDenied ?? false;

  bool get supportsUserLocation {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  Future<bool> requestPermission() async {
    if (!supportsUserLocation) {
      _message = 'User location is not supported on this platform.';
      notifyListeners();
      return false;
    }

    _isRequesting = true;
    _message = 'Requesting location permission...';
    notifyListeners();

    try {
      if (!kIsWeb) {
        final serviceStatus = await Permission.locationWhenInUse.serviceStatus;
        if (serviceStatus.isDisabled) {
          _isRequesting = false;
          _isUserLocationEnabled = false;
          _message = 'Turn on location services to show your position.';
          notifyListeners();
          return false;
        }
      }

      final status = await Permission.locationWhenInUse.request();
      final isGranted = status.isGranted || status.isLimited;
      _permissionStatus = status;
      _isRequesting = false;
      _isUserLocationEnabled = isGranted;
      _hasCenteredOnUserLocation = false;
      _message = isGranted
          ? 'Showing your location.'
          : status.isPermanentlyDenied
          ? 'Location permission is disabled. Open settings to enable it.'
          : 'Location permission was denied.';
      notifyListeners();
      return isGranted;
    } on Exception {
      _isRequesting = false;
      _isUserLocationEnabled = false;
      _message = 'Location permission is unavailable right now.';
      notifyListeners();
      return false;
    }
  }

  void updateUserLocation(GeoCoordinate location) {
    _lastUserLocation = location;
    _hasCenteredOnUserLocation = true;
    notifyListeners();
  }

  void markWaitingForLocation() {
    _message = 'Waiting for your current location...';
    notifyListeners();
  }
}
