import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'package:questmap_app/main.dart';

void main() {
  testWidgets('renders the MapLibre OMT map shell', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const QuestmapApp());

    expect(find.text('Questmap'), findsOneWidget);
    expect(find.byType(MapLibreMap), findsOneWidget);
    expect(find.text('OMT objects'), findsOneWidget);

    final map = tester.widget<MapLibreMap>(find.byType(MapLibreMap));
    expect(map.styleString, equals('assets/omt_style.json'));
    expect(
      map.initialCameraPosition,
      equals(
        const CameraPosition(target: LatLng(37.7749, -122.4194), zoom: 16),
      ),
    );
  });
}
