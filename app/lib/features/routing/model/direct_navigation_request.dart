import '../../../_shared/models/geo_coordinate.dart';
import '../../../_shared/models/transport_mode.dart';

class DirectNavigationRequest {
  const DirectNavigationRequest({
    required this.start,
    required this.destination,
    required this.mode,
    this.departAt,
    this.alternativeCount = 3,
  });

  final GeoCoordinate start;
  final GeoCoordinate destination;
  final TransportMode mode;
  final DateTime? departAt;
  final int alternativeCount;
}
