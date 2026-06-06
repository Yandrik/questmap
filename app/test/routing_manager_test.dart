import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meander/_shared/models/geo_coordinate.dart';
import 'package:meander/_shared/models/transport_mode.dart';
import 'package:meander/_shared/services/api_client.dart';
import 'package:meander/features/routing/manager/routing_manager.dart';
import 'package:meander/features/routing/model/direct_navigation_request.dart';
import 'package:meander/features/routing/services/routing_api_service.dart';
import 'package:meander/features/transit/services/transit_api_service.dart';

void main() {
  test('loads alternatives, selects a route, and toggles navigation', () async {
    final routingDio = Dio(BaseOptions(baseUrl: 'http://api.test'));
    routingDio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response(
              requestOptions: options,
              data: {
                'trip': {
                  'summary': {'length': 1.0, 'time': 300},
                },
                'alternates': [
                  {
                    'trip': {
                      'summary': {'length': 1.2, 'time': 360},
                    },
                  },
                ],
              },
            ),
          );
        },
      ),
    );
    final transitDio = Dio(BaseOptions(baseUrl: 'http://api.test'));
    transitDio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response(
              requestOptions: options,
              data: {'itineraries': <Object>[]},
            ),
          );
        },
      ),
    );
    final manager = RoutingManager(
      RoutingApiService(ApiClient(baseUrl: 'http://api.test', dio: routingDio)),
      TransitApiService(ApiClient(baseUrl: 'http://api.test', dio: transitDio)),
    );

    final candidates = await manager.requestRoutesCommand.runAsync(
      const DirectNavigationRequest(
        start: GeoCoordinate(lat: 48.4, lon: 9.99),
        destination: GeoCoordinate(lat: 48.5, lon: 10),
        mode: TransportMode.walk,
      ),
    );

    expect(candidates, hasLength(2));
    expect(manager.selectedCandidate!.id, 'route-0');

    manager.selectCandidate('route-1');
    expect(manager.selectedCandidate!.id, 'route-1');

    manager.startNavigation();
    expect(manager.isNavigationActive, isTrue);

    manager.stopNavigation();
    expect(manager.isNavigationActive, isFalse);
  });
}
