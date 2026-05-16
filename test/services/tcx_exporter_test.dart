// Verifies that TcxExporter emits Garmin-compatible course points that
// respect each waypoint's stored track distance — the whole reason TCX
// export exists. Hand-built out-and-back fixture with two waypoints at
// the same lat/lon but different cumulative distances; the test confirms
// they emerge as two distinct, monotonically ordered CoursePoint blocks.

import 'package:flutter_test/flutter_test.dart';
import 'package:gpxr/models/gpx_models.dart';
import 'package:gpxr/services/tcx_exporter.dart';
import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';

void main() {
  group('TcxExporter', () {
    test('emits ordered CoursePoint blocks honoring stored trackDistance', () {
      // Simple out-and-back: walk east 100 m, walk west 100 m back to
      // the start. The middle waypoint shares lat/lon with the second
      // waypoint but sits at a different track distance — without the
      // stored trackDistance Garmin (and any nearestOnTrack consumer)
      // would collapse them onto the same pass.
      const start = LatLng(49.0, 18.0);
      const east = LatLng(49.0, 18.0014); // ~100 m east
      final track = GpxTrack(
        name: 'Out and back',
        segments: [
          GpxTrackSegment(
            points: [
              GpxTrackPoint(latLng: start, elevation: 800),
              GpxTrackPoint(latLng: east, elevation: 810),
              GpxTrackPoint(latLng: start, elevation: 800),
            ],
          ),
        ],
      );
      final data = GpxData(
        name: 'Demo',
        tracks: [track],
        waypoints: [
          GpxWaypoint(
            latLng: start,
            elevation: 800,
            name: 'Start',
            type: WaypointType.start,
            trackDistance: 0,
          ),
          GpxWaypoint(
            latLng: east,
            elevation: 810,
            name: 'Turnaround',
            type: WaypointType.summit,
            // Halfway out — the first pass through the east-most point.
            trackDistance: 100,
          ),
          GpxWaypoint(
            latLng: start,
            elevation: 800,
            name: 'Finish',
            type: WaypointType.finish,
            // Same lat/lon as Start but at the end of the round trip.
            trackDistance: 200,
          ),
        ],
      );

      final xml = TcxExporter().export(data: data, tracks: [track]);
      final doc = XmlDocument.parse(xml);

      final coursePoints = doc.findAllElements('CoursePoint').toList();
      expect(coursePoints, hasLength(3));

      // Times must be strictly increasing — Garmin Connect rejects
      // course imports with retrograde course-point times.
      final times = coursePoints
          .map((cp) => cp.getElement('Time')!.innerText)
          .toList();
      final sorted = [...times]..sort();
      expect(times, equals(sorted));

      // Aid-station/medical/summit waypoints must map to the closed
      // TCX PointType enum, not our internal labels.
      final pointTypes = coursePoints
          .map((cp) => cp.getElement('PointType')!.innerText)
          .toList();
      expect(pointTypes, contains('Summit'));
      expect(pointTypes.every(_validTcxPointType), isTrue);

      // DistanceMeters on the lap must match the track total, so a
      // Garmin watch's "course progress" indicator lines up with the
      // app's view of the route length. Tolerance is generous because
      // 100 m at 18° longitude resolves slightly differently per lat
      // when going through the haversine.
      final distance = double.parse(
        doc.findAllElements('DistanceMeters').first.innerText,
      );
      expect(distance, closeTo(200, 10));

      // Each CoursePoint Time must exactly equal one of the Trackpoint
      // Times — Garmin Connect drops CoursePoints whose Time isn't an
      // exact match. We snap to nearest Trackpoint specifically to
      // guarantee this.
      final trackTimes = doc
          .findAllElements('Trackpoint')
          .map((tp) => tp.getElement('Time')!.innerText)
          .toSet();
      for (final t in times) {
        expect(
          trackTimes,
          contains(t),
          reason: 'CoursePoint Time $t must match a Trackpoint Time',
        );
      }
    });

    test('CoursePoint names obey schema (<=10 chars, ASCII, unique)', () {
      // Schema: CoursePointName_t is Token_t with maxLength=10.
      // Garmin Connect strictly enforces — long names, duplicates,
      // and (in practice) non-ASCII characters get the CoursePoint
      // silently dropped on import. Real-world race brief uses
      // diacritics and repeats names on each pass of an out-and-back.
      const start = LatLng(49.0, 18.0);
      const east = LatLng(49.0, 18.0014);
      final track = GpxTrack(
        segments: [
          GpxTrackSegment(
            points: [
              GpxTrackPoint(latLng: start),
              GpxTrackPoint(latLng: east),
              GpxTrackPoint(latLng: start),
            ],
          ),
        ],
      );
      final data = GpxData(
        tracks: [track],
        waypoints: [
          GpxWaypoint(
            latLng: start,
            name: 'Sedlo pod Vysokou',
            type: WaypointType.aidStation,
            trackDistance: 50,
          ),
          GpxWaypoint(
            latLng: east,
            name: 'Chata Třeštík',
            type: WaypointType.aidStation,
            trackDistance: 100,
          ),
          GpxWaypoint(
            latLng: start,
            name: 'Sedlo pod Vysokou 2.',
            type: WaypointType.aidStation,
            trackDistance: 150,
          ),
        ],
      );

      final xml = TcxExporter().export(data: data, tracks: [track]);
      final doc = XmlDocument.parse(xml);
      final names = doc
          .findAllElements('CoursePoint')
          .map((cp) => cp.getElement('Name')!.innerText)
          .toList();

      expect(names, hasLength(3));
      expect(names.toSet(), hasLength(3), reason: 'names must be unique');
      for (final n in names) {
        expect(n.length, lessThanOrEqualTo(10));
        expect(
          RegExp(r'^[\x20-\x7E]+$').hasMatch(n),
          isTrue,
          reason: '"$n" must be pure ASCII for Garmin compatibility',
        );
      }
    });

    test('falls back to projection when trackDistance is missing', () {
      const start = LatLng(49.0, 18.0);
      const east = LatLng(49.0, 18.0014);
      final track = GpxTrack(
        segments: [
          GpxTrackSegment(
            points: [
              GpxTrackPoint(latLng: start),
              GpxTrackPoint(latLng: east),
            ],
          ),
        ],
      );
      final data = GpxData(
        tracks: [track],
        waypoints: [
          // Legacy waypoint without trackDistance — projection should
          // place it near the midpoint of the segment.
          GpxWaypoint(
            latLng: LatLng(49.0, 18.0007),
            name: 'Legacy',
            type: WaypointType.aidStation,
          ),
        ],
      );

      final xml = TcxExporter().export(data: data, tracks: [track]);
      final doc = XmlDocument.parse(xml);
      expect(doc.findAllElements('CoursePoint'), hasLength(1));
      expect(
        doc.findAllElements('PointType').first.innerText,
        equals('First Aid'),
      );
    });

    test('throws when no track points are available', () {
      final track = GpxTrack(segments: [GpxTrackSegment()]);
      final data = GpxData(tracks: [track], waypoints: []);
      expect(
        () => TcxExporter().export(data: data, tracks: [track]),
        throwsStateError,
      );
    });
  });
}

bool _validTcxPointType(String value) {
  // Closed enum from the Garmin TrainingCenterDatabase v2 schema.
  const valid = {
    'Generic',
    'Summit',
    'Valley',
    'Water',
    'Food',
    'Danger',
    'Left',
    'Right',
    'Straight',
    'First Aid',
    'Fourth Category',
    'Third Category',
    'Second Category',
    'First Category',
    'Hors Category',
    'Sprint',
  };
  return valid.contains(value);
}
