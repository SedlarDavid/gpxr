import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

enum WaypointType {
  generic('Generic', 'Flag'),
  aidStation('Aid Station', 'Aid'),
  water('Water', 'Water'),
  food('Food', 'Food'),
  summit('Summit', 'Summit'),
  camp('Camp', 'Camp'),
  parking('Parking', 'Parking'),
  danger('Danger', 'Danger'),
  info('Info', 'Info'),
  start('Start', 'Start'),
  finish('Finish', 'Finish');

  const WaypointType(this.label, this.sym);
  final String label;
  final String sym;

  static WaypointType fromSym(String? sym) {
    if (sym == null) return WaypointType.generic;
    final lower = sym.toLowerCase();
    for (final type in WaypointType.values) {
      if (type.sym.toLowerCase() == lower || type.label.toLowerCase() == lower) {
        return type;
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
  }) : id = id ?? _uuid.v4();

  final String id;
  final LatLng latLng;
  final double? elevation;
  final String? name;
  final String? description;
  final WaypointType type;
  final DateTime? time;

  GpxWaypoint copyWith({
    LatLng? latLng,
    double? elevation,
    String? name,
    String? description,
    WaypointType? type,
    DateTime? time,
  }) {
    return GpxWaypoint(
      id: id,
      latLng: latLng ?? this.latLng,
      elevation: elevation ?? this.elevation,
      name: name ?? this.name,
      description: description ?? this.description,
      type: type ?? this.type,
      time: time ?? this.time,
    );
  }
}

class GpxTrackPoint {
  GpxTrackPoint({
    String? id,
    required this.latLng,
    this.elevation,
    this.time,
  }) : id = id ?? _uuid.v4();

  final String id;
  final LatLng latLng;
  final double? elevation;
  final DateTime? time;

  GpxTrackPoint copyWith({
    LatLng? latLng,
    double? elevation,
    DateTime? time,
  }) {
    return GpxTrackPoint(
      id: id,
      latLng: latLng ?? this.latLng,
      elevation: elevation ?? this.elevation,
      time: time ?? this.time,
    );
  }
}

class GpxTrackSegment {
  GpxTrackSegment({
    String? id,
    List<GpxTrackPoint>? points,
  })  : id = id ?? _uuid.v4(),
        points = points ?? [];

  final String id;
  final List<GpxTrackPoint> points;
}

class GpxTrack {
  GpxTrack({
    String? id,
    this.name,
    List<GpxTrackSegment>? segments,
  })  : id = id ?? _uuid.v4(),
        segments = segments ?? [];

  final String id;
  final String? name;
  final List<GpxTrackSegment> segments;

  List<GpxTrackPoint> get allPoints =>
      segments.expand((s) => s.points).toList();
}

class GpxRoute {
  GpxRoute({
    String? id,
    this.name,
    List<GpxTrackPoint>? points,
  })  : id = id ?? _uuid.v4(),
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
    List<GpxWaypoint>? waypoints,
    List<GpxTrack>? tracks,
    List<GpxRoute>? routes,
  })  : waypoints = waypoints ?? [],
        tracks = tracks ?? [],
        routes = routes ?? [];

  final String? name;
  final String? description;
  final String? author;
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
    List<GpxWaypoint>? waypoints,
    List<GpxTrack>? tracks,
    List<GpxRoute>? routes,
  }) {
    return GpxData(
      name: name ?? this.name,
      description: description ?? this.description,
      author: author ?? this.author,
      waypoints: waypoints ?? this.waypoints,
      tracks: tracks ?? this.tracks,
      routes: routes ?? this.routes,
    );
  }
}
