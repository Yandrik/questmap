import 'package:flutter_test/flutter_test.dart';
import 'package:questmap_app/valhalla_client.dart';

void main() {
  test('serializes a route request using Valhalla OpenAPI field names', () {
    final request = ValhallaRouteRequest(
      locations: const [
        ValhallaLocation(lat: 52.517, lon: 13.388, name: 'Start'),
        ValhallaLocation(lat: 52.529, lon: 13.401, name: 'Finish'),
      ],
      costing: ValhallaCosting.bicycle,
      costingOptions: const {
        'bicycle': {'use_roads': 0.3},
      },
      shapeFormat: ValhallaShapeFormat.geojson,
      language: 'en-US',
    );

    expect(request.toJson(), {
      'locations': [
        {'lat': 52.517, 'lon': 13.388, 'type': 'break', 'name': 'Start'},
        {'lat': 52.529, 'lon': 13.401, 'type': 'break', 'name': 'Finish'},
      ],
      'costing': 'bicycle',
      'costing_options': {
        'bicycle': {'use_roads': 0.3},
      },
      'shape_format': 'geojson',
      'units': 'kilometers',
      'language': 'en-US',
    });
  });

  test('rejects route requests with fewer than two locations', () {
    final request = ValhallaRouteRequest(
      locations: const [ValhallaLocation(lat: 52.517, lon: 13.388)],
    );

    expect(request.toJson, throwsArgumentError);
  });
}
