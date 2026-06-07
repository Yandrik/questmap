import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'package:meander/_shared/models/transit_leg_details.dart';
import 'package:meander/_shared/models/transport_mode.dart';
import 'package:meander/features/map/model/selected_map_target.dart';
import 'package:meander/features/map/widgets/target_details_panel.dart';
import 'package:meander/features/routing/model/navigation_candidate.dart';

void main() {
  testWidgets('shows selected public transport itinerary details', (
    tester,
  ) async {
    final candidate = _transitCandidate();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: TargetDetailsPanel(
              selectedTarget: SelectedMapTarget.waypoint(
                coordinates: const LatLng(48.5, 10),
              ),
              isQuerying: false,
              message: null,
              routeCandidates: [candidate],
              selectedRoute: candidate,
              isRouting: false,
              isNavigationActive: false,
              onNavigate: () {},
              onTrip: () {},
              onSelectRoute: (_) {},
              onStartNavigation: () {},
              onStopNavigation: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Transit itinerary'), findsOneWidget);
    expect(find.text('Walk to Stop A'), findsOneWidget);
    expect(
      find.text('Take Bus 7 toward Downtown from Stop A; get off at Stop B'),
      findsOneWidget,
    );
    expect(find.text('Transit Agency'), findsOneWidget);
    expect(find.text('2 intermediate stops'), findsOneWidget);
    expect(find.text('Turn right on Main Street for 120 m'), findsOneWidget);
  });

  testWidgets('shows transit itinerary during active navigation', (
    tester,
  ) async {
    final candidate = _transitCandidate();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: TargetDetailsPanel(
              selectedTarget: SelectedMapTarget.waypoint(
                coordinates: const LatLng(48.5, 10),
              ),
              isQuerying: false,
              message: null,
              routeCandidates: [candidate],
              selectedRoute: candidate,
              isRouting: false,
              isNavigationActive: true,
              onNavigate: () {},
              onTrip: () {},
              onSelectRoute: (_) {},
              onStartNavigation: () {},
              onStopNavigation: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Transit navigation'), findsOneWidget);
    expect(
      find.text('Take Bus 7 toward Downtown from Stop A; get off at Stop B'),
      findsOneWidget,
    );
    expect(find.text('Stop navigation'), findsOneWidget);
  });

  testWidgets('shows transit itinerary in compact sheet layout', (
    tester,
  ) async {
    final candidate = _transitCandidate();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: TargetDetailsPanel(
              selectedTarget: SelectedMapTarget.waypoint(
                coordinates: const LatLng(48.5, 10),
              ),
              isQuerying: false,
              message: null,
              routeCandidates: [candidate],
              selectedRoute: candidate,
              isRouting: false,
              isNavigationActive: false,
              onNavigate: () {},
              onTrip: () {},
              onSelectRoute: (_) {},
              onStartNavigation: () {},
              onStopNavigation: () {},
              compact: true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Transit itinerary'), findsOneWidget);
    expect(find.text('Walk to Stop A'), findsOneWidget);
  });
}

NavigationCandidate _transitCandidate() {
  return NavigationCandidate(
    id: 'transit-1',
    mode: TransportMode.publicTransport,
    durationSeconds: 1560,
    summaryLabel: 'Bus 7 · 26 min',
    legs: [
      const NavigationLeg(
        mode: TransportMode.walk,
        fromLabel: 'Here',
        toLabel: 'Stop A',
        durationSeconds: 240,
        distanceMeters: 180,
        transitDetails: TransitLegDetails(
          fromLabel: 'Here',
          toLabel: 'Stop A',
          instructions: ['Turn right on Main Street for 120 m'],
        ),
      ),
      NavigationLeg(
        mode: TransportMode.publicTransport,
        fromLabel: 'Stop A',
        toLabel: 'Stop B',
        durationSeconds: 1200,
        displayName: '7',
        transitDetails: TransitLegDetails(
          fromLabel: 'Stop A',
          toLabel: 'Stop B',
          displayName: '7',
          vehicleType: 'Bus',
          headsign: 'Downtown',
          agencyName: 'Transit Agency',
          startTime: DateTime.parse('2026-06-07T10:05:00Z'),
          endTime: DateTime.parse('2026-06-07T10:25:00Z'),
          realTime: true,
          intermediateStopLabels: const ['Middle A', 'Middle B'],
        ),
      ),
    ],
  );
}
