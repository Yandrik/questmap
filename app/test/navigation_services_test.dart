import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meander/_shared/models/geo_coordinate.dart';
import 'package:meander/_shared/models/transport_mode.dart';
import 'package:meander/_shared/services/api_client.dart';
import 'package:meander/features/routing/model/direct_navigation_request.dart';
import 'package:meander/features/routing/services/routing_api_service.dart';
import 'package:meander/features/transit/services/transit_api_service.dart';

void main() {
  test(
    'RoutingApiService posts Valhalla route request through backend',
    () async {
      RequestOptions? seenOptions;
      Object? seenData;
      final dio = Dio(BaseOptions(baseUrl: 'http://api.test'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            seenOptions = options;
            seenData = options.data;
            handler.resolve(
              Response(
                requestOptions: options,
                data: {
                  'trip': {
                    'summary': {'length': 2.4, 'time': 720},
                  },
                },
              ),
            );
          },
        ),
      );

      final service = RoutingApiService(
        ApiClient(baseUrl: 'http://api.test', dio: dio),
      );
      final candidates = await service.route(
        const DirectNavigationRequest(
          start: GeoCoordinate(lat: 48.4, lon: 9.99, label: 'Start'),
          destination: GeoCoordinate(lat: 48.5, lon: 10, label: 'End'),
          mode: TransportMode.bike,
        ),
      );

      expect(seenOptions!.path, '/routing/route');
      expect(seenData, containsPair('costing', 'bicycle'));
      expect(seenData, containsPair('alternates', 3));
      expect(seenData, containsPair('shape_format', 'geojson'));
      expect(candidates.single.summaryLabel, '2.4 km · 12 min');
    },
  );

  test('TransitApiService posts MOTIS body through backend', () async {
    RequestOptions? seenOptions;
    Object? seenData;
    final dio = Dio(BaseOptions(baseUrl: 'http://api.test'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          seenOptions = options;
          seenData = options.data;
          handler.resolve(
            Response(
              requestOptions: options,
              data: {
                'itineraries': [
                  {'id': 'it-1', 'duration': 600, 'legs': <Object>[]},
                ],
              },
            ),
          );
        },
      ),
    );

    final service = TransitApiService(
      ApiClient(baseUrl: 'http://api.test', dio: dio),
    );
    final candidates = await service.planNavigation(
      const DirectNavigationRequest(
        start: GeoCoordinate(lat: 48.4, lon: 9.99),
        destination: GeoCoordinate(lat: 48.5, lon: 10),
        mode: TransportMode.publicTransport,
      ),
    );

    expect(seenOptions!.path, '/transit/plan');
    expect(seenData, containsPair('fromPlace', '48.4,9.99'));
    expect(seenData, containsPair('toPlace', '48.5,10.0'));
    expect(seenData, containsPair('detailedLegs', true));
    expect(seenData, containsPair('detailedTransfers', true));
    expect(seenData, containsPair('transitModes', ['TRANSIT']));
    expect(candidates.single.mode, TransportMode.publicTransport);
  });
}
