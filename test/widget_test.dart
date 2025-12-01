import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Keep your specific project import:
import 'package:eye_gaze_biomarkers/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // 1. Change MyApp to GazeTrackerApp
    await tester.pumpWidget(const EyeTrackingScreen());

    // 2. Since we removed the counter, we simply check if the
    // MaterialApp widget is present to confirm the app started.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
