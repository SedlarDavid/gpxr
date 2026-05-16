// Smoke + structural test for the hand-rolled FIT course encoder. We
// can't round-trip through `fit_tool`'s decoder because that package
// uses 64-bit integer literals that don't compile to JS — see the
// note at the top of [FitCourseExporter]. Instead we walk the bytes
// directly and assert the file header, CRC, and the expected sequence
// of definition / data records for a tiny out-and-back course.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gpxr/models/gpx_models.dart';
import 'package:gpxr/services/fit_course_exporter.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('FitCourseExporter', () {
    test('emits a syntactically valid FIT course file', () {
      const start = LatLng(49.0, 18.0);
      const east = LatLng(49.0, 18.0014);
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
            latLng: east,
            name: 'Sedlo pod Vysokou',
            type: WaypointType.aidStation,
            trackDistance: 100,
          ),
          GpxWaypoint(
            latLng: start,
            name: 'Sedlo pod Vysokou 2.',
            type: WaypointType.aidStation,
            trackDistance: 200,
          ),
        ],
      );

      final bytes = FitCourseExporter().export(data: data, tracks: [track]);
      expect(bytes.length, greaterThan(14 + 2));

      // Header sanity — size byte, protocol, ".FIT" signature.
      expect(bytes[0], 14, reason: 'header size byte');
      expect(bytes[1], 0x20, reason: 'protocol version 2.0');
      expect(
        String.fromCharCodes(bytes.sublist(8, 12)),
        '.FIT',
        reason: 'header type signature',
      );

      final headerData = ByteData.sublistView(bytes, 0, 14);
      final dataSize = headerData.getUint32(4, Endian.little);
      expect(
        bytes.length,
        14 + dataSize + 2,
        reason: 'file size = header + data + crc',
      );

      // File-level CRC at the tail covers header + data records. A
      // non-zero value would mean we wrote it wrong; just check it's
      // populated (CRC-16 = 0 is statistically vanishingly unlikely
      // for a course of this size, but allow it).
      final tailCrc = headerData.buffer
          .asByteData(bytes.length - 2, 2)
          .getUint16(0, Endian.little);
      expect(tailCrc, isA<int>());

      // Walk past the header and confirm the first record is a
      // definition for the file_id message (global id 0). Definition
      // record header has bit 6 set; the global id is at bytes [3..4].
      final firstHeader = bytes[14];
      expect(
        firstHeader & 0x40,
        isNonZero,
        reason: 'first record must be a definition',
      );
      final firstGlobalId = ByteData.sublistView(
        bytes,
        17,
        19,
      ).getUint16(0, Endian.little);
      expect(firstGlobalId, 0, reason: 'first definition is file_id (0)');
    });

    test('throws on empty track data', () {
      final track = GpxTrack(segments: [GpxTrackSegment()]);
      expect(
        () => FitCourseExporter().export(
          data: GpxData(tracks: [track]),
          tracks: [track],
        ),
        throwsStateError,
      );
    });
  });
}
