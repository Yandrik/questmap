import 'package:command_it/command_it.dart';
import 'package:flutter/foundation.dart';

import '../../transit/services/transit_api_service.dart';
import '../model/direct_navigation_request.dart';
import '../model/navigation_candidate.dart';
import '../services/routing_api_service.dart';

class RoutingManager extends ChangeNotifier {
  RoutingManager(this._routingApiService, this._transitApiService) {
    requestRoutesCommand =
        Command.createAsync<DirectNavigationRequest, List<NavigationCandidate>>(
          _requestRoutes,
          initialValue: const [],
          errorFilter: const LocalErrorFilter(),
          debugName: 'requestRoutes',
        );
  }

  final RoutingApiService _routingApiService;
  final TransitApiService _transitApiService;

  late final Command<DirectNavigationRequest, List<NavigationCandidate>>
  requestRoutesCommand;

  List<NavigationCandidate> _candidates = const [];
  NavigationCandidate? _selectedCandidate;
  bool _isNavigationActive = false;
  String? _errorMessage;

  List<NavigationCandidate> get candidates => _candidates;
  NavigationCandidate? get selectedCandidate => _selectedCandidate;
  bool get isNavigationActive => _isNavigationActive;
  String? get errorMessage => _errorMessage;

  Future<List<NavigationCandidate>> _requestRoutes(
    DirectNavigationRequest request,
  ) async {
    _errorMessage = null;
    notifyListeners();

    try {
      final results = request.mode.usesValhalla
          ? await _routingApiService.route(request)
          : await _transitApiService.planNavigation(request);
      _candidates = results;
      _selectedCandidate = results.isEmpty ? null : results.first;
      _isNavigationActive = false;
      notifyListeners();
      return results;
    } on Exception catch (error) {
      _candidates = const [];
      _selectedCandidate = null;
      _isNavigationActive = false;
      _errorMessage = error.toString();
      notifyListeners();
      rethrow;
    }
  }

  void selectCandidate(String candidateId) {
    NavigationCandidate? candidate;
    for (final item in _candidates) {
      if (item.id == candidateId) {
        candidate = item;
        break;
      }
    }
    if (candidate == null) {
      return;
    }
    _selectedCandidate = candidate;
    notifyListeners();
  }

  void startNavigation() {
    if (_selectedCandidate == null) {
      return;
    }
    _isNavigationActive = true;
    notifyListeners();
  }

  void stopNavigation() {
    _isNavigationActive = false;
    notifyListeners();
  }

  void clear() {
    _candidates = const [];
    _selectedCandidate = null;
    _isNavigationActive = false;
    _errorMessage = null;
    notifyListeners();
  }
}
