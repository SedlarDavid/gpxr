import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../models/gpx_models.dart';
import '../services/gpx_parser.dart';
import '../utils/elevation_profile.dart';

enum EditMode { view, addPoint, addWaypoint, deletePoint }

class GpxProvider extends ChangeNotifier {
  final GpxParser _parser = GpxParser();

  GpxData? _data;
  GpxData? get data => _data;

  String? _fileName;
  String? get fileName => _fileName;

  EditMode _editMode = EditMode.view;
  EditMode get editMode => _editMode;

  WaypointType _selectedWaypointType = WaypointType.generic;
  WaypointType get selectedWaypointType => _selectedWaypointType;

  String? _selectedPointId;
  String? get selectedPointId => _selectedPointId;

  bool _showWaypoints = true;
  bool get showWaypoints => _showWaypoints;

  bool _showTrackPoints = false;
  bool get showTrackPoints => _showTrackPoints;

  /// Cumulative distance (meters) of the currently hovered position along
  /// the elevation profile. Kept as a [ValueNotifier] so high-frequency
  /// hover updates don't rebuild the whole widget tree.
  final ValueNotifier<double?> hoverDistance = ValueNotifier(null);

  /// Maximum distance (meters) within which a clicked or existing waypoint
  /// is automatically pulled onto the nearest point of the track. Matches
  /// what Garmin Connect typically tolerates when promoting GPX waypoints
  /// to FIT course points on the watch.
  static const double snapTolerance = 120;

  bool get hasData => _data != null;

  /// Ordered list of every track point across all tracks/segments, used
  /// for profile and snap computations.
  List<GpxTrackPoint> get _allTrackPoints =>
      _data?.tracks.expand((t) => t.allPoints).toList() ??
      const <GpxTrackPoint>[];

  /// Fresh [ElevationProfile] for the current track. Cheap enough to
  /// rebuild per call; callers that need to sample it repeatedly in a
  /// single operation should cache locally.
  ElevationProfile elevationProfile() =>
      ElevationProfile.fromPoints(_allTrackPoints);

  @override
  void dispose() {
    hoverDistance.dispose();
    super.dispose();
  }

  void loadFromString(String xml, String fileName) {
    try {
      _data = _parser.parse(xml);
      _fileName = fileName;
      _editMode = EditMode.view;
      _selectedPointId = null;
      hoverDistance.value = null;
      notifyListeners();
    } catch (e) {
      throw Exception('Failed to parse GPX file: $e');
    }
  }

  String exportToString() {
    if (_data == null) throw Exception('No data to export');
    return _parser.export(_data!);
  }

  void createNew() {
    _data = GpxData(
      name: 'New Route',
      tracks: [
        GpxTrack(
          name: 'Track 1',
          segments: [GpxTrackSegment()],
        ),
      ],
    );
    _fileName = 'new_route.gpx';
    _editMode = EditMode.view;
    _selectedPointId = null;
    notifyListeners();
  }

  void setEditMode(EditMode mode) {
    _editMode = mode;
    notifyListeners();
  }

  void setSelectedWaypointType(WaypointType type) {
    _selectedWaypointType = type;
    notifyListeners();
  }

  void selectPoint(String? id) {
    _selectedPointId = id;
    notifyListeners();
  }

  void toggleWaypoints() {
    _showWaypoints = !_showWaypoints;
    notifyListeners();
  }

  void toggleTrackPoints() {
    _showTrackPoints = !_showTrackPoints;
    notifyListeners();
  }

  // Track point operations
  void addTrackPoint(LatLng latLng, {int? index}) {
    if (_data == null) return;
    final tracks = _data!.tracks;
    if (tracks.isEmpty) {
      tracks.add(GpxTrack(
        name: 'Track 1',
        segments: [GpxTrackSegment()],
      ));
    }
    final segment = tracks.first.segments.first;
    final point = GpxTrackPoint(latLng: latLng);
    if (index != null && index <= segment.points.length) {
      segment.points.insert(index, point);
    } else {
      segment.points.add(point);
    }
    _data = _data!.copyWith(tracks: tracks);
    notifyListeners();
  }

  void removeTrackPoint(String id) {
    if (_data == null) return;
    for (final track in _data!.tracks) {
      for (final seg in track.segments) {
        seg.points.removeWhere((p) => p.id == id);
      }
    }
    if (_selectedPointId == id) _selectedPointId = null;
    notifyListeners();
  }

  void moveTrackPoint(String id, LatLng newLatLng) {
    if (_data == null) return;
    for (final track in _data!.tracks) {
      for (final seg in track.segments) {
        final idx = seg.points.indexWhere((p) => p.id == id);
        if (idx != -1) {
          seg.points[idx] = seg.points[idx].copyWith(latLng: newLatLng);
          notifyListeners();
          return;
        }
      }
    }
  }

  void reorderTrackPoints(int oldIndex, int newIndex) {
    if (_data == null) return;
    if (_data!.tracks.isEmpty) return;
    final segment = _data!.tracks.first.segments.first;
    if (oldIndex < newIndex) newIndex--;
    final point = segment.points.removeAt(oldIndex);
    segment.points.insert(newIndex, point);
    notifyListeners();
  }

  // Waypoint operations
  void addWaypoint(LatLng latLng, {String? name, WaypointType? type}) {
    if (_data == null) return;
    // Snap to nearest point on the track when the click lands within the
    // snap tolerance so the resulting GPX can be promoted to Garmin course
    // points on export. Also lift elevation from the track.
    final profile = elevationProfile();
    final nearest = profile.nearestOnTrack(latLng);
    LatLng resolved = latLng;
    double? elevation;
    if (nearest != null && nearest.distanceToLineMeters <= snapTolerance) {
      resolved = nearest.latLng;
      elevation = profile.sampleAtDistance(nearest.distance).elevation;
    }
    final wpt = GpxWaypoint(
      latLng: resolved,
      elevation: elevation,
      name: name ?? '${(type ?? _selectedWaypointType).label} ${_data!.waypoints.length + 1}',
      type: type ?? _selectedWaypointType,
    );
    _data!.waypoints.add(wpt);
    notifyListeners();
  }

  /// Merges [waypoints] (typically scraped from a race page) into the
  /// current GPX, snapping each one onto the track when it's within
  /// [snapTolerance]. Waypoints further than the tolerance are kept where
  /// they are so the user can still see them on the map and review them.
  ///
  /// Returns the number of waypoints that were actually imported.
  int importWaypoints(List<GpxWaypoint> waypoints) {
    if (_data == null) return 0;
    final profile = elevationProfile();
    int added = 0;
    for (final incoming in waypoints) {
      var wpt = incoming;
      if (!profile.isEmpty) {
        final nearest = profile.nearestOnTrack(incoming.latLng);
        if (nearest != null && nearest.distanceToLineMeters <= snapTolerance) {
          final sample = profile.sampleAtDistance(nearest.distance);
          wpt = incoming.copyWith(
            latLng: nearest.latLng,
            elevation: incoming.elevation ?? sample.elevation,
          );
        }
      }
      _data!.waypoints.add(wpt);
      added++;
    }
    if (added > 0) notifyListeners();
    return added;
  }

  /// Pulls an existing waypoint onto the closest point of the track,
  /// regardless of snap tolerance. Used by the sidebar "snap" action for
  /// waypoints that were placed off-track and need to be turned into
  /// course points.
  void snapWaypointToTrack(String id) {
    if (_data == null) return;
    final idx = _data!.waypoints.indexWhere((w) => w.id == id);
    if (idx == -1) return;
    final profile = elevationProfile();
    final nearest = profile.nearestOnTrack(_data!.waypoints[idx].latLng);
    if (nearest == null) return;
    final sample = profile.sampleAtDistance(nearest.distance);
    _data!.waypoints[idx] = _data!.waypoints[idx].copyWith(
      latLng: nearest.latLng,
      elevation: sample.elevation,
    );
    notifyListeners();
  }

  /// Projects [wpt] onto the current track and returns the cumulative
  /// distance (meters) and perpendicular offset, or null if there is no
  /// track to project onto. Used by the sidebar and elevation chart to
  /// show "km from start" / off-track warnings.
  WaypointTrackInfo? waypointTrackInfo(GpxWaypoint wpt) {
    final profile = elevationProfile();
    if (profile.isEmpty) return null;
    final nearest = profile.nearestOnTrack(wpt.latLng);
    if (nearest == null) return null;
    return WaypointTrackInfo(
      distance: nearest.distance,
      offsetMeters: nearest.distanceToLineMeters,
      onTrack: nearest.distanceToLineMeters <= snapTolerance,
    );
  }

  void removeWaypoint(String id) {
    if (_data == null) return;
    _data!.waypoints.removeWhere((w) => w.id == id);
    if (_selectedPointId == id) _selectedPointId = null;
    notifyListeners();
  }

  void updateWaypoint(String id, {String? name, String? description, WaypointType? type, LatLng? latLng}) {
    if (_data == null) return;
    final idx = _data!.waypoints.indexWhere((w) => w.id == id);
    if (idx == -1) return;
    _data!.waypoints[idx] = _data!.waypoints[idx].copyWith(
      name: name,
      description: description,
      type: type,
      latLng: latLng,
    );
    notifyListeners();
  }

  void moveWaypoint(String id, LatLng newLatLng) {
    if (_data == null) return;
    final idx = _data!.waypoints.indexWhere((w) => w.id == id);
    if (idx != -1) {
      _data!.waypoints[idx] = _data!.waypoints[idx].copyWith(latLng: newLatLng);
      notifyListeners();
    }
  }

  void reorderWaypoints(int oldIndex, int newIndex) {
    if (_data == null) return;
    if (oldIndex < newIndex) newIndex--;
    final wpt = _data!.waypoints.removeAt(oldIndex);
    _data!.waypoints.insert(newIndex, wpt);
    notifyListeners();
  }

  /// Reverses the order of all track and route points so the direction of
  /// travel is inverted (start becomes finish and vice versa).
  void reverseRoute() {
    if (_data == null) return;
    for (final track in _data!.tracks) {
      for (final seg in track.segments) {
        final reversed = seg.points.reversed.toList();
        seg.points
          ..clear()
          ..addAll(reversed);
      }
      final revSegs = track.segments.reversed.toList();
      track.segments
        ..clear()
        ..addAll(revSegs);
    }
    for (final r in _data!.routes) {
      final reversed = r.points.reversed.toList();
      r.points
        ..clear()
        ..addAll(reversed);
    }
    hoverDistance.value = null;
    notifyListeners();
  }

  void updateRouteName(String name) {
    if (_data == null) return;
    _data = _data!.copyWith(name: name);
    notifyListeners();
  }

  // Insert a track point at the closest position on the track to the given point
  void insertTrackPointSmart(LatLng latLng) {
    if (_data == null) return;
    if (_data!.tracks.isEmpty) {
      addTrackPoint(latLng);
      return;
    }
    final segment = _data!.tracks.first.segments.first;
    if (segment.points.length < 2) {
      addTrackPoint(latLng);
      return;
    }

    // Find the segment between two consecutive points that is closest to the new point
    int bestIndex = segment.points.length;
    double bestDist = double.infinity;
    const distance = Distance();

    for (int i = 0; i < segment.points.length - 1; i++) {
      final a = segment.points[i].latLng;
      final b = segment.points[i + 1].latLng;
      final mid = LatLng((a.latitude + b.latitude) / 2, (a.longitude + b.longitude) / 2);
      final d = distance.as(LengthUnit.Meter, latLng, mid);
      if (d < bestDist) {
        bestDist = d;
        bestIndex = i + 1;
      }
    }

    addTrackPoint(latLng, index: bestIndex);
  }
}

/// Result of projecting a waypoint onto the current track.
class WaypointTrackInfo {
  WaypointTrackInfo({
    required this.distance,
    required this.offsetMeters,
    required this.onTrack,
  });

  /// Cumulative distance along the track (meters) at the projection.
  final double distance;

  /// Perpendicular distance (meters) from the waypoint to the track.
  final double offsetMeters;

  /// Whether [offsetMeters] is within [GpxProvider.snapTolerance].
  final bool onTrack;
}
