import '../../../_shared/models/transport_mode.dart';
import '../../../_shared/services/api_client.dart';
import '../model/direct_navigation_request.dart';
import '../model/navigation_candidate.dart';
import '../model/valhalla_route_request.dart';

class RoutingApiService {
  const RoutingApiService(this._apiClient);

  final ApiClient _apiClient;

  Future<List<NavigationCandidate>> route(
    DirectNavigationRequest request,
  ) async {
    if (!request.mode.usesValhalla) {
      throw ArgumentError.value(
        request.mode,
        'mode',
        'Public transport routes must use TransitApiService.',
      );
    }

    final body = ValhallaRouteRequest(
      locations: [
        ValhallaLocation(
          lat: request.start.lat,
          lon: request.start.lon,
          name: request.start.label,
        ),
        ValhallaLocation(
          lat: request.destination.lat,
          lon: request.destination.lon,
          name: request.destination.label,
        ),
      ],
      costing: _valhallaCosting(request.mode),
      alternates: request.alternativeCount,
      directionsType: ValhallaDirectionsType.none,
      shapeFormat: ValhallaShapeFormat.geojson,
    ).toJson();

    final response = await _apiClient.postJson('/routing/route', data: body);
    return NavigationCandidateParser.fromValhalla(
      json: response,
      mode: request.mode,
    );
  }

  static ValhallaCosting _valhallaCosting(TransportMode mode) {
    return switch (mode) {
      TransportMode.walk => ValhallaCosting.pedestrian,
      TransportMode.bike => ValhallaCosting.bicycle,
      TransportMode.drive => ValhallaCosting.auto,
      TransportMode.publicTransport => throw ArgumentError.value(mode),
    };
  }
}
