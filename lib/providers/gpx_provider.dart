import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../models/gpx_models.dart';
import '../services/gpx_parser.dart';

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

  bool get hasData => _data != null;

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
    final wpt = GpxWaypoint(
      latLng: latLng,
      name: name ?? '${(type ?? _selectedWaypointType).label} ${_data!.waypoints.length + 1}',
      type: type ?? _selectedWaypointType,
    );
    _data!.waypoints.add(wpt);
    notifyListeners();
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
