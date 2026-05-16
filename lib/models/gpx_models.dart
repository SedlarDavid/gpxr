import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// What the user is using GPXR for. Drives climb grading thresholds and
/// grade-color ramps so a 10% pitch reads "moderate" for a trail runner
/// and "very steep" for a road cyclist. Persisted in localStorage so the
/// choice survives reloads.
enum ActivityType {
  trailRun('Trail run'),
  bike('Bike');

  const ActivityType(this.label);
  final String label;

  static ActivityType fromName(String? name) {
    if (name == null) return ActivityType.trailRun;
    for (final t in ActivityType.values) {
      if (t.name == name) return t;
    }
    return ActivityType.trailRun;
  }
}

enum WaypointType {
  generic(
    'Generic',
    sym: 'Flag, Blue',
    gpxType: 'Waypoint',
    aliases: ['Flag', 'Waypoint', 'Generic', 'Pin, Blue'],
  ),
  aidStation(
    'Aid Station',
    sym: 'First Aid',
    gpxType: 'Aid Station',
    aliases: ['Aid', 'First Aid Kit', 'Aid Station'],
  ),
  medical(
    'Medical',
    sym: 'Medical Facility',
    gpxType: 'Medical',
    aliases: ['Medical', 'Hospital', 'Rescue', 'First Aid'],
  ),
  water(
    'Water',
    sym: 'Water Source',
    gpxType: 'Water',
    aliases: ['Water', 'Drinking Water'],
  ),
  food(
    'Food',
    sym: 'Restaurant',
    gpxType: 'Food',
    aliases: ['Food', 'Food Source', 'Fast Food'],
  ),
  summit(
    'Summit',
    sym: 'Summit',
    gpxType: 'Summit',
    aliases: ['Peak', 'Mountain'],
  ),
  camp(
    'Camp',
    sym: 'Campground',
    gpxType: 'Camp',
    aliases: ['Camp', 'Campsite', 'Tent'],
  ),
  parking(
    'Parking',
    sym: 'Parking Area',
    gpxType: 'Parking',
    aliases: ['Parking'],
  ),
  danger(
    'Danger',
    sym: 'Skull and Crossbones',
    gpxType: 'Danger',
    aliases: ['Danger', 'Danger Area', 'Warning'],
  ),
  info(
    'Info',
    sym: 'Information',
    gpxType: 'Information',
    aliases: ['Info', 'Information'],
  ),
  start(
    'Start',
    sym: 'Flag, Green',
    gpxType: 'Start',
    aliases: ['Start', 'Begin', 'Navaid, Green'],
  ),
  finish(
    'Finish',
    sym: 'Flag, Red',
    gpxType: 'Finish',
    aliases: ['Finish', 'End', 'Navaid, Red'],
  );

  const WaypointType(
    this.label, {
    required this.sym,
    required this.gpxType,
    this.aliases = const [],
  });

  final String label;

  /// Canonical Garmin `<sym>` name written into exported GPX so firmware
  /// and Garmin Connect can map the waypoint to the correct course-point
  /// icon when the track is converted to a FIT course file.
  final String sym;

  /// Value written into the optional `<type>` element, picked up by some
  /// tools as a secondary classification hint.
  final String gpxType;

  /// Legacy/alternate names we still accept when parsing existing GPX
  /// files so round-tripping older exports keeps the right type.
  final List<String> aliases;

  static WaypointType fromSym(String? sym) {
    if (sym == null) return WaypointType.generic;
    final lower = sym.toLowerCase().trim();
    if (lower.isEmpty) return WaypointType.generic;
    for (final type in WaypointType.values) {
      if (type.sym.toLowerCase() == lower ||
          type.label.toLowerCase() == lower ||
          type.gpxType.toLowerCase() == lower) {
        return type;
      }
      for (final alias in type.aliases) {
        if (alias.toLowerCase() == lower) return type;
      }
    }
    return WaypointType.generic;
  }
}

class GpxWaypoint {
  GpxWaypoint({
    String? id,
    required this.latLng,
    this.elevation,
    this.name,
    this.description,
    this.type = WaypointType.generic,
    this.time,
    this.cutoff,
    this.trackDistance,
  }) : id = id ?? _uuid.v4();

  final String id;
  final LatLng latLng;
  final double? elevation;
  final String? name;
  final String? description;
  final WaypointType type;
  final DateTime? time;

  /// Free-form cutoff string — typically a clock time like "12:30" or an
  /// elapsed duration like "1:23:45" when an aid station has a hard cut-
  /// off the runner has to clear by. Round-tripped via the GPX
  /// `<extensions><gpxr:cutoff>` element so other tools that don't know
  /// about it ignore it silently.
  final String? cutoff;

  /// Cumulative distance along the track (meters) when the waypoint was
  /// placed by km, snapped to track, or auto-generated. Stored explicitly
  /// because on out-and-back / lollipop routes the same lat/lon can lie
  /// on the track at multiple km values, and projecting back from lat/lon
  /// would pick an arbitrary pass. Cleared whenever the waypoint is moved
  /// to a free lat/lon, so projection takes over again.
  final double? trackDistance;

  GpxWaypoint copyWith({
    LatLng? latLng,
    double? elevation,
    String? name,
    String? description,
    WaypointType? type,
    DateTime? time,
    String? cutoff,
    bool clearCutoff = false,
    double? trackDistance,
    bool clearTrackDistance = false,
  }) {
    return GpxWaypoint(
      id: id,
      latLng: latLng ?? this.latLng,
      elevation: elevation ?? this.elevation,
      name: name ?? this.name,
      description: description ?? this.description,
      type: type ?? this.type,
      time: time ?? this.time,
      cutoff: clearCutoff ? null : (cutoff ?? this.cutoff),
      trackDistance: clearTrackDistance
          ? null
          : (trackDistance ?? this.trackDistance),
    );
  }
}

class GpxTrackPoint {
  GpxTrackPoint({String? id, required this.latLng, this.elevation, this.time})
    : id = id ?? _uuid.v4();

  final String id;
  final LatLng latLng;
  final double? elevation;
  final DateTime? time;

  GpxTrackPoint copyWith({LatLng? latLng, double? elevation, DateTime? time}) {
    return GpxTrackPoint(
      id: id,
      latLng: latLng ?? this.latLng,
      elevation: elevation ?? this.elevation,
      time: time ?? this.time,
    );
  }
}

class GpxTrackSegment {
  GpxTrackSegment({String? id, List<GpxTrackPoint>? points})
    : id = id ?? _uuid.v4(),
      points = points ?? [];

  final String id;
  final List<GpxTrackPoint> points;
}

class GpxTrack {
  GpxTrack({String? id, this.name, List<GpxTrackSegment>? segments})
    : id = id ?? _uuid.v4(),
      segments = segments ?? [];

  final String id;
  final String? name;
  final List<GpxTrackSegment> segments;

  List<GpxTrackPoint> get allPoints =>
      segments.expand((s) => s.points).toList();
}

class GpxRoute {
  GpxRoute({String? id, this.name, List<GpxTrackPoint>? points})
    : id = id ?? _uuid.v4(),
      points = points ?? [];

  final String id;
  final String? name;
  final List<GpxTrackPoint> points;
}

class GpxData {
  GpxData({
    this.name,
    this.description,
    this.author,
    this.sourceUrl,
    List<GpxWaypoint>? waypoints,
    List<GpxTrack>? tracks,
    List<GpxRoute>? routes,
  }) : waypoints = waypoints ?? [],
       tracks = tracks ?? [],
       routes = routes ?? [];

  final String? name;
  final String? description;
  final String? author;

  /// First `<link href="...">` found in the GPX. Used to detect files
  /// exported from sources we can enrich (e.g. tracedetrail.fr race
  /// pages, which ship the track but not the waypoints).
  final String? sourceUrl;

  final List<GpxWaypoint> waypoints;
  final List<GpxTrack> tracks;
  final List<GpxRoute> routes;

  List<LatLng> get allTrackPoints =>
      tracks.expand((t) => t.allPoints).map((p) => p.latLng).toList();

  List<LatLng> get allRoutePoints =>
      routes.expand((r) => r.points).map((p) => p.latLng).toList();

  List<LatLng> get allLinePoints {
    final points = <LatLng>[];
    points.addAll(allTrackPoints);
    points.addAll(allRoutePoints);
    return points;
  }

  GpxData copyWith({
    String? name,
    String? description,
    String? author,
    String? sourceUrl,
    List<GpxWaypoint>? waypoints,
    List<GpxTrack>? tracks,
    List<GpxRoute>? routes,
  }) {
    return GpxData(
      name: name ?? this.name,
      description: description ?? this.description,
      author: author ?? this.author,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      waypoints: waypoints ?? this.waypoints,
      tracks: tracks ?? this.tracks,
      routes: routes ?? this.routes,
    );
  }
}
