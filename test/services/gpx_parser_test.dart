// Verifies GPX round-trip preserves our custom `gpxr:` extensions on
// waypoints — namely the cutoff time and the cumulative track distance
// we depend on for correct km display on out-and-back / lollipop routes.
//
// Regression: `findAllElements('trackDistance')` without an explicit
// namespace matches the qualified name `trackDistance`, NOT
// `gpxr:trackDistance` (which is how we emit it). Re-importing one of
// our own GPX files quietly dropped the stored distance, so the
// projection-based fallback kicked in and waypoints landed on the
// wrong pass again.

import 'package:flutter_test/flutter_test.dart';
import 'package:gpxr/models/gpx_models.dart';
import 'package:gpxr/services/gpx_parser.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('GpxParser', () {
    test('round-trips cutoff and trackDistance on waypoints', () {
      final original = GpxData(
        name: 'Out and back',
        tracks: [
          GpxTrack(
            name: 'main',
            segments: [
              GpxTrackSegment(
                points: [
                  GpxTrackPoint(latLng: const LatLng(49.0, 18.0)),
                  GpxTrackPoint(latLng: const LatLng(49.0, 18.001)),
                ],
              ),
            ],
          ),
        ],
        waypoints: [
          GpxWaypoint(
            latLng: const LatLng(49.0, 18.0005),
            name: 'Aid 1',
            type: WaypointType.aidStation,
            cutoff: '12:30',
            trackDistance: 9700,
          ),
          GpxWaypoint(
            latLng: const LatLng(49.0, 18.0005),
            name: 'Aid 2 (return)',
            type: WaypointType.aidStation,
            trackDistance: 20300,
          ),
        ],
      );

      final parser = GpxParser();
      final xml = parser.export(original);
      final reparsed = parser.parse(xml);

      expect(reparsed.waypoints, hasLength(2));
      expect(reparsed.waypoints[0].cutoff, '12:30');
      expect(reparsed.waypoints[0].trackDistance, 9700);
      expect(reparsed.waypoints[1].trackDistance, 20300);
    });
  });
}
