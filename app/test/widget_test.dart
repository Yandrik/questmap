import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:watch_it/watch_it.dart';

import 'package:meander/app/meander.dart';
import 'package:meander/locator.dart';

void main() {
  setUp(configureDependencies);

  tearDown(() async {
    await di.reset();
  });

  testWidgets('renders the MapLibre OMT map shell', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MeanderApp());

    expect(find.text('Meander'), findsOneWidget);
    expect(find.byType(MapLibreMap), findsOneWidget);
    expect(find.text('Map target'), findsOneWidget);

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
