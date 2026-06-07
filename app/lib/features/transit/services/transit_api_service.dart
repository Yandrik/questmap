import '../../../_shared/services/api_client.dart';
import '../../routing/model/direct_navigation_request.dart';
import '../../routing/model/navigation_candidate.dart';
import '../model/motis_plan_request.dart';

class TransitApiService {
  const TransitApiService(this._apiClient);

  final ApiClient _apiClient;

  Future<List<NavigationCandidate>> planNavigation(
    DirectNavigationRequest request,
  ) async {
    final body = MotisPlanRequest(
      fromPlace: request.start.motisPlace,
      toPlace: request.destination.motisPlace,
      time: request.departAt,
      detailedLegs: true,
      detailedTransfers: true,
      joinInterlinedLegs: false,
      directModes: const [],
      preTransitModes: const [MotisMode.walk],
      postTransitModes: const [MotisMode.walk],
      transitModes: const [MotisMode.transit],
      numItineraries: request.alternativeCount + 1,
      numLegAlternatives: request.alternativeCount,
      timetableView: false,
      language: const ['de', 'en'],
    ).toJson();

    final response = await _apiClient.postJson('/transit/plan', data: body);
    return NavigationCandidateParser.fromMotis(response);
  }
}
