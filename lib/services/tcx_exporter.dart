import 'package:xml/xml.dart';

import '../models/gpx_models.dart';
import '../utils/elevation_profile.dart';

/// Builds a Garmin Training Center Database v2 (TCX) `<Course>` document
/// for the loaded GPX data, with each waypoint emitted as an ordered
/// `<CoursePoint>`.
///
/// GPX waypoints are unordered POIs — Garmin Connect places them on a
/// course by projecting lat/lon onto the nearest track segment. On
/// out-and-back or lollipop routes that pass the same point twice the
/// projection is ambiguous, so aid stations land on the wrong pass. TCX
/// `<CoursePoint>` blocks carry an explicit `<Time>` that ties the
/// course point to a specific track point, removing the ambiguity.
///
/// Times are synthesized from a fixed base instant using a constant
/// pace (`secondsPerMeter`) — Garmin only cares about ordering and
/// monotonicity for course imports.
class TcxExporter {
  TcxExporter({this.secondsPerMeter = 0.45});

  /// Pacing used to synthesize track-point and course-point times.
  /// Default 0.45 s/m ≈ 8 km/h, comfortable trail-running pace. Garmin
  /// course import only requires monotonic times, not realistic ones.
  final double secondsPerMeter;

  static final DateTime _baseTime = DateTime.utc(2000, 1, 1);

  /// Builds TCX for the given [data], flattening every visible track in
  /// [tracks] into a single `<Track>` so a course always has one
  /// continuous ordered line. Waypoints with [GpxWaypoint.trackDistance]
  /// set are emitted at exactly that distance; others fall back to
  /// projection onto the track.
  String export({required GpxData data, required List<GpxTrack> tracks}) {
    final profile = ElevationProfile.fromSegments(
      tracks.map((t) => t.allPoints).toList(),
    );
    if (profile.isEmpty) {
      throw StateError(
        'Cannot export an empty course — load a track with at least one point.',
      );
    }

    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element(
      'TrainingCenterDatabase',
      nest: () {
        builder.attribute(
          'xmlns',
          'http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2',
        );
        builder.attribute(
          'xmlns:xsi',
          'http://www.w3.org/2001/XMLSchema-instance',
        );
        builder.attribute(
          'xsi:schemaLocation',
          'http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2 '
              'http://www.garmin.com/xmlschemas/TrainingCenterDatabasev2.xsd',
        );
        builder.element(
          'Courses',
          nest: () => _buildCourse(builder, data, tracks, profile),
        );
      },
    );
    return builder.buildDocument().toXmlString(pretty: true);
  }

  void _buildCourse(
    XmlBuilder builder,
    GpxData data,
    List<GpxTrack> tracks,
    ElevationProfile profile,
  ) {
    final rawName =
        _firstNonBlank([
          data.name,
          tracks.isNotEmpty ? tracks.first.name : null,
        ]) ??
        'Course';
    // The Garmin v2 XSD types `Course/Name` as RestrictedToken_t with
    // maxLength=15. Garmin Connect strictly enforces the limit and
    // some firmwares choke on Unicode in this position — ASCII-fold
    // and hard-cap so the course actually imports.
    final courseName = _truncate(
      _foldDiacritics(rawName).replaceAll(RegExp(r'\s+'), ' ').trim(),
      15,
    );

    final totalSeconds = (profile.totalDistance * secondsPerMeter).ceil().clamp(
      1,
      1 << 30,
    );
    final startLatLng = profile.points.first.latLng;
    final endLatLng = profile.points.last.latLng;

    builder.element(
      'Course',
      nest: () {
        builder.element('Name', nest: courseName);
        builder.element(
          'Lap',
          nest: () {
            builder.element('TotalTimeSeconds', nest: totalSeconds.toString());
            builder.element(
              'DistanceMeters',
              nest: profile.totalDistance.toStringAsFixed(2),
            );
            builder.element(
              'BeginPosition',
              nest: () {
                builder.element(
                  'LatitudeDegrees',
                  nest: startLatLng.latitude.toString(),
                );
                builder.element(
                  'LongitudeDegrees',
                  nest: startLatLng.longitude.toString(),
                );
              },
            );
            builder.element(
              'EndPosition',
              nest: () {
                builder.element(
                  'LatitudeDegrees',
                  nest: endLatLng.latitude.toString(),
                );
                builder.element(
                  'LongitudeDegrees',
                  nest: endLatLng.longitude.toString(),
                );
              },
            );
            builder.element('Intensity', nest: 'Active');
          },
        );
        _buildTrack(builder, profile);
        _buildCoursePoints(builder, data, profile);
      },
    );
  }

  void _buildTrack(XmlBuilder builder, ElevationProfile profile) {
    builder.element(
      'Track',
      nest: () {
        for (int i = 0; i < profile.points.length; i++) {
          final pt = profile.points[i];
          final cum = profile.distances[i];
          builder.element(
            'Trackpoint',
            nest: () {
              builder.element('Time', nest: _isoTime(cum));
              builder.element(
                'Position',
                nest: () {
                  builder.element(
                    'LatitudeDegrees',
                    nest: pt.latLng.latitude.toString(),
                  );
                  builder.element(
                    'LongitudeDegrees',
                    nest: pt.latLng.longitude.toString(),
                  );
                },
              );
              final ele = pt.elevation ?? profile.elevations[i];
              if (ele != null) {
                builder.element('AltitudeMeters', nest: ele.toString());
              }
              builder.element('DistanceMeters', nest: cum.toStringAsFixed(2));
            },
          );
        }
      },
    );
  }

  void _buildCoursePoints(
    XmlBuilder builder,
    GpxData data,
    ElevationProfile profile,
  ) {
    final pairs = <_CoursePointEntry>[];
    for (final wpt in data.waypoints) {
      final stored = wpt.trackDistance;
      double? distance;
      if (stored != null && stored >= 0 && stored <= profile.totalDistance) {
        distance = stored;
      } else {
        // Fall back to projection — covers hand-placed waypoints from
        // legacy GPX files that don't carry a stored track distance.
        final nearest = profile.nearestOnTrack(wpt.latLng);
        if (nearest != null) distance = nearest.distance;
      }
      if (distance == null) continue;
      pairs.add(_CoursePointEntry(waypoint: wpt, distance: distance));
    }
    // Order matters: TCX consumers expect course points to advance
    // monotonically through the track, so sort by along-track distance
    // before emitting.
    pairs.sort((a, b) => a.distance.compareTo(b.distance));

    final usedNames = <String>{};
    for (final entry in pairs) {
      final wpt = entry.waypoint;
      // Snap to the closest *real* Trackpoint instead of using an
      // interpolated sample. Garmin Connect's TCX importer matches
      // CoursePoints to Trackpoints by Time, and silently drops any
      // CoursePoint whose Time doesn't line up with an existing
      // Trackpoint — so we reuse the snapped Trackpoint's exact
      // distance for Time generation and its lat/lon for Position so
      // the two can't drift apart.
      final idx = profile.nearestIndexForDistance(entry.distance);
      final trackPoint = profile.points[idx];
      final snappedDistance = profile.distances[idx];
      final name = _coursePointName(
        _firstNonBlank([wpt.name]) ?? 'Waypoint',
        usedNames,
      );
      builder.element(
        'CoursePoint',
        nest: () {
          // CoursePointName_t in the v2 schema caps at 10 chars
          // (whitespace-collapsed xsd:token). Garmin Connect strictly
          // enforces this on import, silently dropping CoursePoints
          // whose Name is longer or duplicates another Name in the
          // same Course — both passes through "Sedlo pod Vysokou"
          // truncate to the same 10-char prefix, so we ASCII-fold and
          // de-duplicate with a trailing counter to keep all of them.
          builder.element('Name', nest: name);
          builder.element('Time', nest: _isoTime(snappedDistance));
          builder.element(
            'Position',
            nest: () {
              builder.element(
                'LatitudeDegrees',
                nest: trackPoint.latLng.latitude.toString(),
              );
              builder.element(
                'LongitudeDegrees',
                nest: trackPoint.latLng.longitude.toString(),
              );
            },
          );
          final ele = wpt.elevation ?? trackPoint.elevation;
          if (ele != null) {
            builder.element('AltitudeMeters', nest: ele.toString());
          }
          builder.element('PointType', nest: _pointTypeFor(wpt.type));
          final notes = _firstNonBlank([wpt.description, wpt.cutoff]);
          if (notes != null) builder.element('Notes', nest: notes);
        },
      );
    }
  }

  String _isoTime(double cumulativeMeters) {
    final secs = (cumulativeMeters * secondsPerMeter).round();
    final t = _baseTime.add(Duration(seconds: secs));
    // Manual format — avoid milliseconds/microseconds, which Garmin
    // Connect's older course importer is fussy about.
    final y = t.year.toString().padLeft(4, '0');
    final mo = t.month.toString().padLeft(2, '0');
    final d = t.day.toString().padLeft(2, '0');
    final h = t.hour.toString().padLeft(2, '0');
    final mi = t.minute.toString().padLeft(2, '0');
    final s = t.second.toString().padLeft(2, '0');
    return '$y-$mo-${d}T$h:$mi:${s}Z';
  }

  /// Maps our richer [WaypointType] palette down to the closed set of
  /// Garmin TCX `<PointType>` enum values. Anything without a clean
  /// equivalent falls back to `Generic`, which Garmin watches render as
  /// a neutral pin.
  static String _pointTypeFor(WaypointType type) {
    switch (type) {
      case WaypointType.aidStation:
      case WaypointType.medical:
        return 'First Aid';
      case WaypointType.water:
        return 'Water';
      case WaypointType.food:
        return 'Food';
      case WaypointType.summit:
        return 'Summit';
      case WaypointType.danger:
        return 'Danger';
      case WaypointType.start:
      case WaypointType.finish:
      case WaypointType.camp:
      case WaypointType.parking:
      case WaypointType.info:
      case WaypointType.generic:
        return 'Generic';
    }
  }

  static String? _firstNonBlank(List<String?> candidates) {
    for (final c in candidates) {
      if (c == null) continue;
      final t = c.trim();
      if (t.isNotEmpty) return t;
    }
    return null;
  }

  static String _truncate(String s, int max) =>
      s.length <= max ? s : s.substring(0, max);

  /// Produces a `CoursePointName_t`-compatible name (max 10 chars,
  /// whitespace-collapsed) that is unique within the current export.
  /// Strips diacritics so the byte-strict Token_t form survives
  /// Connect's import — `Š`, `ě`, `ř` etc otherwise occasionally trip
  /// older firmware code paths. Duplicates get a trailing ` 2`, ` 3`
  /// counter, inserted *inside* the 10-char budget by truncating the
  /// base further when needed.
  static String _coursePointName(String raw, Set<String> used) {
    final base = _truncate(
      _foldDiacritics(raw).replaceAll(RegExp(r'\s+'), ' ').trim(),
      10,
    );
    final fallback = base.isEmpty ? 'WP' : base;
    if (used.add(fallback)) return fallback;
    var counter = 2;
    while (true) {
      final suffix = ' $counter';
      final budget = 10 - suffix.length;
      final trimmed = fallback.length > budget
          ? fallback.substring(0, budget).trimRight()
          : fallback;
      final candidate = '$trimmed$suffix';
      if (used.add(candidate)) return candidate;
      counter++;
    }
  }

  /// Maps common Czech / Western European diacritics to their plain
  /// ASCII base letter. Not a full Unicode normalizer — just the set
  /// the user community actually puts in race-brief waypoint names.
  static String _foldDiacritics(String input) {
    const folds = {
      'á': 'a',
      'à': 'a',
      'â': 'a',
      'ä': 'a',
      'ã': 'a',
      'å': 'a',
      'č': 'c',
      'ç': 'c',
      'ď': 'd',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'ě': 'e',
      'í': 'i',
      'ì': 'i',
      'î': 'i',
      'ï': 'i',
      'ľ': 'l',
      'ĺ': 'l',
      'ň': 'n',
      'ñ': 'n',
      'ó': 'o',
      'ò': 'o',
      'ô': 'o',
      'ö': 'o',
      'õ': 'o',
      'ø': 'o',
      'ř': 'r',
      'ŕ': 'r',
      'š': 's',
      'ş': 's',
      'ß': 'ss',
      'ť': 't',
      'ú': 'u',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ů': 'u',
      'ý': 'y',
      'ÿ': 'y',
      'ž': 'z',
      'ź': 'z',
      'ż': 'z',
      'Á': 'A',
      'À': 'A',
      'Â': 'A',
      'Ä': 'A',
      'Ã': 'A',
      'Å': 'A',
      'Č': 'C',
      'Ç': 'C',
      'Ď': 'D',
      'É': 'E',
      'È': 'E',
      'Ê': 'E',
      'Ë': 'E',
      'Ě': 'E',
      'Í': 'I',
      'Ì': 'I',
      'Î': 'I',
      'Ï': 'I',
      'Ľ': 'L',
      'Ĺ': 'L',
      'Ň': 'N',
      'Ñ': 'N',
      'Ó': 'O',
      'Ò': 'O',
      'Ô': 'O',
      'Ö': 'O',
      'Õ': 'O',
      'Ø': 'O',
      'Ř': 'R',
      'Ŕ': 'R',
      'Š': 'S',
      'Ş': 'S',
      'Ť': 'T',
      'Ú': 'U',
      'Ù': 'U',
      'Û': 'U',
      'Ü': 'U',
      'Ů': 'U',
      'Ý': 'Y',
      'Ž': 'Z',
      'Ź': 'Z',
      'Ż': 'Z',
    };
    final buf = StringBuffer();
    for (final ch in input.split('')) {
      buf.write(folds[ch] ?? ch);
    }
    return buf.toString();
  }
}

class _CoursePointEntry {
  _CoursePointEntry({required this.waypoint, required this.distance});

  final GpxWaypoint waypoint;
  final double distance;
}
