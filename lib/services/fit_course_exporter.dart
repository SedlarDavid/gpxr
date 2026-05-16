import 'dart:typed_data';

import '../models/gpx_models.dart';
import '../utils/elevation_profile.dart';

/// Builds a Garmin FIT course (`.fit`) file in pure Dart. Required
/// because the popular `fit_tool` package uses 64-bit integer literals
/// that dart2js can't compile, and GPXR is a web app.
///
/// The Courses → Import path in Garmin Connect strips imported
/// `<CoursePoint>` elements out of TCX files but reliably honors the
/// `course_point` messages inside a FIT course file — that's the only
/// path that gets aid stations onto a watch at the right km on each
/// pass of an out-and-back / lollipop route.
///
/// Track-point and course-point timestamps are synthesized from a
/// constant pace; Garmin only requires monotonic ordering for course
/// files, not realistic timing.
class FitCourseExporter {
  FitCourseExporter({this.secondsPerMeter = 0.45, this.sport = _sportRunning});

  /// Pace used to synthesize record / course_point timestamps. Default
  /// 0.45 s/m ≈ 8 km/h, a comfortable trail-running pace.
  final double secondsPerMeter;

  /// FIT `sport` enum value written into the `course` message — Garmin
  /// watches use it to pick the activity profile when the course is
  /// started. Defaults to running (1); pass `2` for cycling.
  final int sport;

  /// Builds and returns the raw FIT bytes. Throws [StateError] when
  /// [tracks] has no points — a FIT course needs at least one record.
  Uint8List export({required GpxData data, required List<GpxTrack> tracks}) {
    final profile = ElevationProfile.fromSegments(
      tracks.map((t) => t.allPoints).toList(),
    );
    if (profile.isEmpty) {
      throw StateError(
        'Cannot export an empty course — load a track with at least one point.',
      );
    }

    final body = _Writer();

    // FIT epoch is 1989-12-31 00:00:00 UTC; we set the course's base
    // time arbitrarily on that epoch (relative ordering is all Garmin
    // cares about for course files).
    const baseSeconds = 0;
    int tsAt(double meters) => baseSeconds + (meters * secondsPerMeter).round();

    final totalSecs = tsAt(profile.totalDistance);
    final unixNowEpoch =
        (DateTime.now().millisecondsSinceEpoch ~/ 1000) - _fitEpochUnixSeconds;

    _emitFileId(body, timeCreated: unixNowEpoch);
    _emitCourse(
      body,
      name:
          _firstNonBlank([
            data.name,
            tracks.isNotEmpty ? tracks.first.name : null,
          ]) ??
          'Course',
    );
    _emitEvent(body, eventType: _eventTypeStart, timestamp: baseSeconds);
    _emitRecords(body, profile, tsAt);
    _emitCoursePoints(body, data, profile, tsAt);
    _emitEvent(body, eventType: _eventTypeStopAll, timestamp: totalSecs);
    _emitLap(
      body,
      profile: profile,
      startTime: baseSeconds,
      endTime: totalSecs,
    );

    return _wrapWithHeaderAndCrc(body.bytes);
  }

  // ----- record emitters -------------------------------------------------

  void _emitFileId(_Writer w, {required int timeCreated}) {
    final def = _MessageDef(
      localId: 0,
      globalId: _globalFileId,
      fields: [
        _Field(0, 1, _baseEnum), // type
        _Field(1, 2, _baseUint16), // manufacturer
        _Field(2, 2, _baseUint16), // product
        _Field(3, 4, _baseUint32z), // serial_number
        _Field(4, 4, _baseUint32), // time_created
      ],
    );
    w.writeDefinition(def);

    w.writeDataHeader(def.localId);
    w.writeUint8(6); // course
    w.writeUint16(255); // development manufacturer
    w.writeUint16(0); // product
    w.writeUint32(0xDEADBEEF); // serial
    w.writeUint32(timeCreated);
  }

  void _emitCourse(_Writer w, {required String name}) {
    // Course name field is fixed-width and the FIT writer falls back
    // to `?` for non-ASCII bytes — ASCII-fold so Czech / Western EU
    // diacritics render as their base letter ("Valašský" → "Valassky")
    // instead of the unreadable "Vala?sk?".
    final folded = _foldDiacritics(name);
    final encoded = _encodeStringFixed(folded, 32);
    final def = _MessageDef(
      localId: 1,
      globalId: _globalCourse,
      fields: [
        _Field(5, encoded.length, _baseString), // name
        _Field(4, 1, _baseEnum), // sport
      ],
    );
    w.writeDefinition(def);

    w.writeDataHeader(def.localId);
    w.writeBytes(encoded);
    w.writeUint8(sport);
  }

  void _emitEvent(_Writer w, {required int eventType, required int timestamp}) {
    final def = _MessageDef(
      localId: 2,
      globalId: _globalEvent,
      fields: [
        _Field(253, 4, _baseUint32), // timestamp
        _Field(0, 1, _baseEnum), // event
        _Field(1, 1, _baseEnum), // event_type
      ],
    );
    w.writeDefinition(def);

    w.writeDataHeader(def.localId);
    w.writeUint32(timestamp);
    w.writeUint8(0); // event=timer
    w.writeUint8(eventType);
  }

  void _emitRecords(
    _Writer w,
    ElevationProfile profile,
    int Function(double) tsAt,
  ) {
    final def = _MessageDef(
      localId: 3,
      globalId: _globalRecord,
      fields: [
        _Field(253, 4, _baseUint32), // timestamp
        _Field(0, 4, _baseSint32), // position_lat (semicircles)
        _Field(1, 4, _baseSint32), // position_long
        _Field(5, 4, _baseUint32), // distance (m * 100)
        _Field(2, 2, _baseUint16), // altitude (m * 5 + 500)
      ],
    );
    w.writeDefinition(def);

    for (int i = 0; i < profile.points.length; i++) {
      final pt = profile.points[i];
      final cum = profile.distances[i];
      final ele = pt.elevation ?? profile.elevations[i];

      w.writeDataHeader(def.localId);
      w.writeUint32(tsAt(cum));
      w.writeSint32(_toSemicircles(pt.latLng.latitude));
      w.writeSint32(_toSemicircles(pt.latLng.longitude));
      w.writeUint32((cum * 100).round());
      // 0xFFFF is FIT's invalid sentinel for uint16 fields — used when
      // a point has no recorded elevation.
      w.writeUint16(ele == null ? 0xFFFF : ((ele * 5) + 500).round());
    }
  }

  void _emitCoursePoints(
    _Writer w,
    GpxData data,
    ElevationProfile profile,
    int Function(double) tsAt,
  ) {
    final entries = <_CpEntry>[];
    for (final wpt in data.waypoints) {
      final stored = wpt.trackDistance;
      double? distance;
      if (stored != null && stored >= 0 && stored <= profile.totalDistance) {
        distance = stored;
      } else {
        final nearest = profile.nearestOnTrack(wpt.latLng);
        if (nearest != null) distance = nearest.distance;
      }
      if (distance == null) continue;
      entries.add(_CpEntry(wpt: wpt, distance: distance));
    }
    entries.sort((a, b) => a.distance.compareTo(b.distance));
    if (entries.isEmpty) return;

    final def = _MessageDef(
      localId: 4,
      globalId: _globalCoursePoint,
      fields: [
        _Field(254, 2, _baseUint16), // message_index
        _Field(1, 4, _baseUint32), // timestamp
        _Field(2, 4, _baseSint32), // position_lat
        _Field(3, 4, _baseSint32), // position_long
        _Field(4, 4, _baseUint32), // distance
        _Field(6, _coursePointNameLen, _baseString), // name
        _Field(5, 1, _baseEnum), // type
      ],
    );
    w.writeDefinition(def);

    final usedNames = <String>{};
    for (int i = 0; i < entries.length; i++) {
      final e = entries[i];
      // Snap to nearest real record so the course point shares an exact
      // timestamp with a track point — Garmin firmware matches alerts
      // on timestamp/distance equality.
      final idx = profile.nearestIndexForDistance(e.distance);
      final pt = profile.points[idx];
      final snappedDistance = profile.distances[idx];
      final name = _coursePointName(
        _firstNonBlank([e.wpt.name]) ?? 'Waypoint',
        usedNames,
      );

      w.writeDataHeader(def.localId);
      w.writeUint16(i);
      w.writeUint32(tsAt(snappedDistance));
      w.writeSint32(_toSemicircles(pt.latLng.latitude));
      w.writeSint32(_toSemicircles(pt.latLng.longitude));
      w.writeUint32((snappedDistance * 100).round());
      w.writeBytes(_encodeStringFixed(name, _coursePointNameLen));
      w.writeUint8(_typeFor(e.wpt.type));
    }
  }

  void _emitLap(
    _Writer w, {
    required ElevationProfile profile,
    required int startTime,
    required int endTime,
  }) {
    final def = _MessageDef(
      localId: 5,
      globalId: _globalLap,
      fields: [
        _Field(253, 4, _baseUint32), // timestamp
        _Field(2, 4, _baseUint32), // start_time
        _Field(3, 4, _baseSint32), // start_position_lat
        _Field(4, 4, _baseSint32), // start_position_long
        _Field(5, 4, _baseSint32), // end_position_lat
        _Field(6, 4, _baseSint32), // end_position_long
        _Field(7, 4, _baseUint32), // total_elapsed_time (ms; scale=1000)
        _Field(8, 4, _baseUint32), // total_timer_time
        _Field(9, 4, _baseUint32), // total_distance (m * 100)
      ],
    );
    w.writeDefinition(def);

    final first = profile.points.first.latLng;
    final last = profile.points.last.latLng;
    final elapsedMs = (endTime - startTime) * 1000;

    w.writeDataHeader(def.localId);
    w.writeUint32(endTime);
    w.writeUint32(startTime);
    w.writeSint32(_toSemicircles(first.latitude));
    w.writeSint32(_toSemicircles(first.longitude));
    w.writeSint32(_toSemicircles(last.latitude));
    w.writeSint32(_toSemicircles(last.longitude));
    w.writeUint32(elapsedMs);
    w.writeUint32(elapsedMs);
    w.writeUint32((profile.totalDistance * 100).round());
  }

  // ----- header / crc wrapper -------------------------------------------

  Uint8List _wrapWithHeaderAndCrc(Uint8List body) {
    final header = ByteData(_fitHeaderSize);
    header.setUint8(0, _fitHeaderSize);
    header.setUint8(1, 0x20); // protocol version 2.0
    header.setUint16(2, 2140, Endian.little); // profile version
    header.setUint32(4, body.length, Endian.little); // data_size
    // ".FIT" ASCII
    header.setUint8(8, 0x2E);
    header.setUint8(9, 0x46);
    header.setUint8(10, 0x49);
    header.setUint8(11, 0x54);
    final headerCrc = _crc16(header.buffer.asUint8List(0, 12));
    header.setUint16(12, headerCrc, Endian.little);

    final headerBytes = header.buffer.asUint8List();
    final totalCrc = _crc16(Uint8List.fromList([...headerBytes, ...body]));

    final out = Uint8List(headerBytes.length + body.length + 2);
    out.setRange(0, headerBytes.length, headerBytes);
    out.setRange(headerBytes.length, headerBytes.length + body.length, body);
    out.buffer.asByteData().setUint16(
      headerBytes.length + body.length,
      totalCrc,
      Endian.little,
    );
    return out;
  }

  // ----- helpers --------------------------------------------------------

  static int _toSemicircles(double degrees) =>
      (degrees * (2147483648.0 / 180.0)).round();

  static Uint8List _encodeStringFixed(String input, int length) {
    final bytes = Uint8List(length);
    // FIT strings are null-terminated UTF-8 padded out to the field size.
    final encoded = input.codeUnits;
    final copyLen = encoded.length < length ? encoded.length : length - 1;
    for (var i = 0; i < copyLen; i++) {
      final cp = encoded[i];
      bytes[i] = cp < 0x80 ? cp : 0x3F; // non-ASCII → '?'
    }
    return bytes;
  }

  /// Maps our richer waypoint palette down to the closed FIT
  /// course_point enum the watch firmware recognises. Anything without
  /// a clean equivalent collapses to `generic` (0), which renders as a
  /// neutral flag on the device.
  static int _typeFor(WaypointType type) {
    switch (type) {
      case WaypointType.aidStation:
      case WaypointType.medical:
        return 9; // first_aid
      case WaypointType.water:
        return 3;
      case WaypointType.food:
        return 4;
      case WaypointType.summit:
        return 1;
      case WaypointType.danger:
        return 5;
      case WaypointType.start:
        return 24; // segment_start
      case WaypointType.finish:
        return 25; // segment_end
      case WaypointType.camp:
      case WaypointType.parking:
      case WaypointType.info:
      case WaypointType.generic:
        return 0; // generic
    }
  }

  /// FIT course_point.name is a 16-byte field. Garmin Connect dedupes
  /// course points by name within a single course, so duplicates from
  /// two passes through the same aid station get a trailing counter
  /// fitted inside the 16-byte budget. ASCII-fold prevents UTF-8 bytes
  /// from overflowing the field — non-ASCII chars become `?`.
  static String _coursePointName(String raw, Set<String> used) {
    final base = _foldDiacritics(raw.replaceAll(RegExp(r'\s+'), ' ').trim());
    final truncated = base.length > _coursePointNameLen - 1
        ? base.substring(0, _coursePointNameLen - 1)
        : base;
    final fallback = truncated.isEmpty ? 'WP' : truncated;
    if (used.add(fallback)) return fallback;
    var counter = 2;
    while (true) {
      final suffix = ' $counter';
      final budget = (_coursePointNameLen - 1) - suffix.length;
      final trimmed = fallback.length > budget
          ? fallback.substring(0, budget).trimRight()
          : fallback;
      final candidate = '$trimmed$suffix';
      if (used.add(candidate)) return candidate;
      counter++;
    }
  }

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

  static String? _firstNonBlank(List<String?> candidates) {
    for (final c in candidates) {
      if (c == null) continue;
      final t = c.trim();
      if (t.isNotEmpty) return t;
    }
    return null;
  }
}

class _CpEntry {
  _CpEntry({required this.wpt, required this.distance});

  final GpxWaypoint wpt;
  final double distance;
}

class _MessageDef {
  _MessageDef({
    required this.localId,
    required this.globalId,
    required this.fields,
  });

  final int localId;
  final int globalId;
  final List<_Field> fields;
}

class _Field {
  const _Field(this.id, this.size, this.baseType);

  final int id;
  final int size;
  final int baseType;
}

/// Simple growable byte buffer with little-endian writes for the FIT
/// numeric types we emit. Keeps the encoder free of `dart:ffi` /
/// platform-specific paths so it compiles cleanly to JS.
class _Writer {
  final List<int> _buf = <int>[];

  Uint8List get bytes => Uint8List.fromList(_buf);

  void writeUint8(int v) => _buf.add(v & 0xFF);

  void writeUint16(int v) {
    _buf.add(v & 0xFF);
    _buf.add((v >> 8) & 0xFF);
  }

  void writeUint32(int v) {
    _buf.add(v & 0xFF);
    _buf.add((v >> 8) & 0xFF);
    _buf.add((v >> 16) & 0xFF);
    _buf.add((v >> 24) & 0xFF);
  }

  void writeSint32(int v) {
    // Two's complement is automatic at the byte level — just mask.
    writeUint32(v & 0xFFFFFFFF);
  }

  void writeBytes(Uint8List bytes) {
    _buf.addAll(bytes);
  }

  /// Emits a definition record (header + definition body) for [def].
  void writeDefinition(_MessageDef def) {
    // Definition record header: bit 6 = 1 (definition), low nibble =
    // local message type.
    _buf.add(0x40 | (def.localId & 0x0F));
    _buf.add(0); // reserved
    _buf.add(0); // architecture: little-endian
    writeUint16(def.globalId);
    _buf.add(def.fields.length);
    for (final f in def.fields) {
      _buf.add(f.id);
      _buf.add(f.size);
      _buf.add(f.baseType);
    }
  }

  /// Emits a data-record header (bit 6 = 0, low nibble = local id).
  void writeDataHeader(int localId) {
    _buf.add(localId & 0x0F);
  }
}

// FIT global message numbers (from the FIT profile).
const int _globalFileId = 0;
const int _globalLap = 19;
const int _globalRecord = 20;
const int _globalEvent = 21;
const int _globalCourse = 31;
const int _globalCoursePoint = 32;

// FIT base type bytes. The high bit (0x80) marks fields that need
// endian-aware byte ordering — required by the spec for multi-byte
// numeric fields.
const int _baseEnum = 0x00;
const int _baseUint16 = 0x84;
const int _baseSint32 = 0x85;
const int _baseUint32 = 0x86;
const int _baseString = 0x07;
const int _baseUint32z = 0x8C;

// FIT event_type enum.
const int _eventTypeStart = 0;
const int _eventTypeStopAll = 4;

// FIT course_point.name is a 16-byte field; we reserve the final byte
// for the NUL terminator (FIT strings are NUL-terminated when shorter
// than the field width).
const int _coursePointNameLen = 16;

// FIT file header is fixed at 14 bytes (size + protocol + profile +
// data_size + ".FIT" + header_crc).
const int _fitHeaderSize = 14;

// FIT epoch (1989-12-31 00:00:00 UTC) expressed as Unix seconds.
const int _fitEpochUnixSeconds = 631065600;

// FIT sport enum values.
const int _sportRunning = 1;

/// FIT CRC-16 (per the FIT SDK reference implementation).
int _crc16(Uint8List data) {
  const table = [
    0x0000,
    0xCC01,
    0xD801,
    0x1400,
    0xF001,
    0x3C00,
    0x2800,
    0xE401,
    0xA001,
    0x6C00,
    0x7800,
    0xB401,
    0x5000,
    0x9C01,
    0x8801,
    0x4400,
  ];
  int crc = 0;
  for (final b in data) {
    var tmp = table[crc & 0xF];
    crc = (crc >> 4) & 0x0FFF;
    crc = crc ^ tmp ^ table[b & 0xF];
    tmp = table[crc & 0xF];
    crc = (crc >> 4) & 0x0FFF;
    crc = crc ^ tmp ^ table[(b >> 4) & 0xF];
  }
  return crc & 0xFFFF;
}
