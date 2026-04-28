// Smoke test — boots the GPXR app and confirms the empty-state copy
// renders. Replaces the auto-generated counter-app stub from
// `flutter create` (the App was renamed to GpxrApp long ago).

import 'package:flutter_test/flutter_test.dart';
import 'package:gpxr/main.dart';

void main() {
  testWidgets('App boots into empty state', (WidgetTester tester) async {
    await tester.pumpWidget(const GpxrApp());
    expect(find.text('No route loaded'), findsOneWidget);
  });
}
