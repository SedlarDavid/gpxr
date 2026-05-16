import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:latlong2/latlong.dart';
import 'package:web/web.dart' as web;
import '../models/gpx_models.dart';
import '../services/gpx_parser.dart';
import '../services/fit_course_exporter.dart';
import '../services/tcx_exporter.dart';
import '../utils/climb_detector.dart';
import '../utils/descent_detector.dart';
import '../utils/elevation_profile.dart';
import '../utils/geo_utils.dart';

enum EditMode { view, addPoint, addWaypoint, deletePoint }

const _activityStorageKey = 'gpxr.activity.v1';
const _routeColorStorageKey = 'gpxr.routeColor.v1';

/// Palette of route colors offered in the map's color picker. The first
/// entry is the default — picked to be a Strava-style red so the track
/// stays visible over the magenta-dashed tourist trails on the Mapy.com
/// outdoor layer (and the indigo we used before blended right in).
const List<Color> kRouteColorPresets = [
  Color(0xFFE11900), // strava red (default)
  Color(0xFFEF4444), // bright red
  Color(0xFFF97316), // orange
  Color(0xFFFFC107), // amber
  Color(0xFF22C55E), // green
  Color(0xFF06B6D4), // cyan
  Color(0xFF2563EB), // blue
  Color(0xFF6366F1), // indigo (legacy default)
  Color(0xFF8B5CF6), // violet
  Color(0xFF111827), // near-black
];

class GpxProvider extends ChangeNotifier {
  GpxProvider() {
    final activity = web.window.localStorage.getItem(_activityStorageKey);
    if (activity != null) _activityType = ActivityType.fromName(activity);
    final color = web.window.localStorage.getItem(_routeColorStorageKey);
    if (color != null) {
      final v = int.tryParse(color);
      if (v != null) _routeColor = Color(v);
    }
  }

  final GpxParser _parser = GpxParser();
  final TcxExporter _tcxExporter = TcxExporter();
  final FitCourseExporter _fitExporter = FitCourseExporter();

  GpxData? _data;
  GpxData? get data => _data;

  String? _fileName;
  String? get fileName => _fileName;

  EditMode _editMode = EditMode.view;
  EditMode get editMode => _editMode;

  WaypointType _selectedWaypointType = WaypointType.generic;
  WaypointType get selectedWaypointType => _selectedWaypointType;

  ActivityType _activityType = ActivityType.trailRun;
  ActivityType get activityType => _activityType;

  void setActivityType(ActivityType t) {
    if (_activityType == t) return;
    _activityType = t;
    web.window.localStorage.setItem(_activityStorageKey, t.name);
    notifyListeners();
  }

  Color _routeColor = kRouteColorPresets.first;
  Color get routeColor => _routeColor;

  void setRouteColor(Color c) {
    if (_routeColor == c) return;
    _routeColor = c;
    // Color.toARGB32() is the modern replacement for the deprecated
    // .value getter; storing as a base-10 int keeps the localStorage
    // entry trivially round-trippable across reloads.
    web.window.localStorage.setItem(
      _routeColorStorageKey,
      c.toARGB32().toString(),
    );
    notifyListeners();
  }

  /// Per-track color overrides. The first track in a single-file load
  /// falls back to [_routeColor]; merged tracks each get their own
  /// distinct entry from [kRouteColorPresets] so the user can tell them
  /// apart on the map at a glance.
  final Map<String, Color> _trackColors = {};

  /// Track IDs whose polyline + stats contribution are hidden. Stored as
  /// IDs (rather than indices) so reordering/removing tracks doesn't
  /// silently re-toggle which track is hidden.
  final Set<String> _hiddenTrackIds = <String>{};

  Color colorForTrack(String trackId) => _trackColors[trackId] ?? _routeColor;

  void setTrackColor(String trackId, Color color) {
    _trackColors[trackId] = color;
    notifyListeners();
  }

  bool isTrackVisible(String trackId) => !_hiddenTrackIds.contains(trackId);

  void toggleTrackVisibility(String trackId) {
    if (_hiddenTrackIds.contains(trackId)) {
      _hiddenTrackIds.remove(trackId);
    } else {
      _hiddenTrackIds.add(trackId);
    }
    hoverDistance.value = null;
    _notifyProfileChanged();
  }

  /// Tracks the user currently has visible. Stats, climbs, descents and
  /// the elevation profile all derive from this so hiding a track
  /// removes it from the combined picture as well as the map.
  List<GpxTrack> get visibleTracks =>
      _data?.tracks.where((t) => isTrackVisible(t.id)).toList() ??
      const <GpxTrack>[];

  /// Assigns a unique override color to [track] from [kRouteColorPresets]
  /// preferring entries not already used by the current data and not
  /// equal to [_routeColor]. Falls back to cycling through the palette
  /// when every preset is already taken.
  void _assignAutoColor(GpxTrack track) {
    final used = {_routeColor, ..._trackColors.values};
    for (final c in kRouteColorPresets) {
      if (!used.contains(c)) {
        _trackColors[track.id] = c;
        return;
      }
    }
    final idx = (_data?.tracks.length ?? 0) % kRouteColorPresets.length;
    _trackColors[track.id] = kRouteColorPresets[idx];
  }

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

  /// (startDistance, endDistance) of the climb currently hovered in the
  /// sidebar's climbs tab, used to highlight its extent on the map.
  /// Null when no climb is hovered.
  final ValueNotifier<(double, double)?> hoveredClimbRange = ValueNotifier(
    null,
  );

  /// (startDistance, endDistance) of the descent currently hovered in
  /// the sidebar's descents tab. Symmetric counterpart of
  /// [hoveredClimbRange] — used to spotlight the segment on the map and
  /// elevation chart so trail runners can see where the knee-punishing
  /// downhills fall.
  final ValueNotifier<(double, double)?> hoveredDescentRange = ValueNotifier(
    null,
  );

  /// Maximum distance (meters) within which a clicked or existing waypoint
  /// is automatically pulled onto the nearest point of the track. Matches
  /// what Garmin Connect typically tolerates when promoting GPX waypoints
  /// to FIT course points on the watch.
  static const double snapTolerance = 120;

  bool get hasData => _data != null;

  /// Cached profile / climbs / descents and per-waypoint projections.
  /// Recomputing the profile on every call was the #1 hover-lag cause:
  /// it not only re-walked 45k haversines per frame but also defeated
  /// the map's screen-cache for the hover hit-test, which keys on
  /// `identical(profile)` — a fresh instance per call meant the cache
  /// was rebuilt every hover frame too. Invalidated by
  /// [_invalidateProfileCaches] from every mutator that changes the
  /// underlying track points or visibility.
  ElevationProfile? _cachedProfile;
  List<Climb>? _cachedClimbs;
  List<Descent>? _cachedDescents;
  final Map<String, NearestOnTrack?> _waypointProjections = {};

  void _invalidateProfileCaches() {
    _cachedProfile = null;
    _cachedClimbs = null;
    _cachedDescents = null;
    _waypointProjections.clear();
  }

  /// Invalidates the cached profile/climbs/descents/projections and
  /// fires [notifyListeners]. Use from any mutator that changes track
  /// points or visibility. Cosmetic mutators (edit mode, color picker,
  /// selection) should keep using bare [notifyListeners] so the cache
  /// survives unrelated UI churn.
  void _notifyProfileChanged() {
    _invalidateProfileCaches();
    notifyListeners();
  }

  /// Drops the cached projection for a single waypoint without
  /// touching the profile/climbs caches. Used when a waypoint moves
  /// or is renamed but the underlying track is unchanged.
  void _invalidateWaypointProjection(String id) {
    _waypointProjections.remove(id);
  }

  /// [ElevationProfile] across the visible tracks, cached. Built via
  /// [ElevationProfile.fromSegments] so cumulative distance does *not*
  /// span the gap between two merged tracks (otherwise four tracks
  /// joined Bergen↔Voss↔…↔Oslo would inflate by hundreds of phantom km
  /// of haversine jumps), and so climbs/descents reset at boundaries.
  ElevationProfile elevationProfile() {
    return _cachedProfile ??= ElevationProfile.fromSegments(
      visibleTracks.map((t) => t.allPoints).toList(),
    );
  }

  /// Cached climb list across the current visible profile. Mirrors
  /// [elevationProfile] for invalidation. Use this from UI builders
  /// instead of calling [ClimbDetector.detect] directly so a hover or
  /// tab switch doesn't re-scan 45k points.
  List<Climb> climbs() {
    return _cachedClimbs ??= ClimbDetector.detect(elevationProfile());
  }

  /// Cached descent list — same caching contract as [climbs].
  List<Descent> descents() {
    return _cachedDescents ??= DescentDetector.detect(elevationProfile());
  }

  /// Cached per-waypoint projection onto the current track. Used by
  /// the stats panel and elevation chart, which previously called
  /// [ElevationProfile.nearestOnTrack] (O(N)) for every waypoint on
  /// every Consumer rebuild — at 45k profile points × 50 waypoints
  /// that was 2.25M haversines per stats rebuild.
  NearestOnTrack? nearestOnTrackForWaypoint(GpxWaypoint wpt) {
    return _waypointProjections.putIfAbsent(wpt.id, () {
      final profile = elevationProfile();
      if (profile.isEmpty) return null;
      return profile.nearestOnTrack(wpt.latLng);
    });
  }

  @override
  void dispose() {
    hoverDistance.dispose();
    hoveredClimbRange.dispose();
    hoveredDescentRange.dispose();
    super.dispose();
  }

  void loadFromString(String xml, String fileName) {
    try {
      _data = _parser.parse(xml);
      _fileName = fileName;
      _editMode = EditMode.view;
      _selectedPointId = null;
      hoverDistance.value = null;
      _trackColors.clear();
      _hiddenTrackIds.clear();
      // First track keeps the user's chosen routeColor (so single-file
      // loads look identical to before). Any extra tracks shipped in
      // the same GPX get auto-assigned distinct colors.
      final tracks = _data!.tracks;
      // Single-track GPX often puts the route name only in <metadata>
      // and leaves <trk><name> empty. Mirror it onto the track so the
      // sidebar and re-export carry the name instead of "Track 1".
      final dataName = _data!.name?.trim();
      if (tracks.length == 1 &&
          dataName != null &&
          dataName.isNotEmpty &&
          (tracks[0].name == null || tracks[0].name!.trim().isEmpty)) {
        final old = tracks[0];
        tracks[0] = GpxTrack(
          id: old.id,
          name: dataName,
          segments: old.segments,
        );
      }
      for (int i = 1; i < tracks.length; i++) {
        _assignAutoColor(tracks[i]);
      }
      _notifyProfileChanged();
    } catch (e) {
      throw Exception('Failed to parse GPX file: $e');
    }
  }

  /// Parses [xml] and merges its tracks (and routes/waypoints) into the
  /// currently loaded GpxData. Each incoming track gets a fresh,
  /// distinct color so the user can tell merged tracks apart on the
  /// map. Falls back to [loadFromString] when there is no current data.
  ///
  /// Returns the number of tracks that were appended.
  int appendFromString(String xml, String fileName) {
    if (_data == null) {
      loadFromString(xml, fileName);
      return _data?.tracks.length ?? 0;
    }
    try {
      final incoming = _parser.parse(xml);
      // Default the appended track names to the source filename when
      // the GPX itself didn't set one — that's the only label the user
      // has to distinguish merged tracks in the Tracks tab.
      final stem = _fileNameStem(fileName);
      for (int i = 0; i < incoming.tracks.length; i++) {
        final t = incoming.tracks[i];
        final named = (t.name == null || t.name!.trim().isEmpty)
            ? GpxTrack(
                id: t.id,
                name: incoming.tracks.length == 1 ? stem : '$stem (${i + 1})',
                segments: t.segments,
              )
            : t;
        _data!.tracks.add(named);
        _assignAutoColor(named);
      }
      _data!.routes.addAll(incoming.routes);
      _data!.waypoints.addAll(incoming.waypoints);
      hoverDistance.value = null;
      _notifyProfileChanged();
      return incoming.tracks.length;
    } catch (e) {
      throw Exception('Failed to parse GPX file: $e');
    }
  }

  /// Removes the track with [id] from the current data, along with its
  /// visibility/color state. No-op when no data is loaded or no track
  /// matches.
  void removeTrack(String id) {
    if (_data == null) return;
    final removed = _data!.tracks.length;
    _data!.tracks.removeWhere((t) => t.id == id);
    if (_data!.tracks.length == removed) return;
    _trackColors.remove(id);
    _hiddenTrackIds.remove(id);
    hoverDistance.value = null;
    _notifyProfileChanged();
  }

  /// Renames the track with [id]. Used by the Tracks tab so users can
  /// give merged tracks meaningful labels (e.g. "Day 1", "Day 2").
  void setTrackName(String id, String name) {
    if (_data == null) return;
    final idx = _data!.tracks.indexWhere((t) => t.id == id);
    if (idx == -1) return;
    final old = _data!.tracks[idx];
    _data!.tracks[idx] = GpxTrack(
      id: old.id,
      name: name.trim().isEmpty ? null : name.trim(),
      segments: old.segments,
    );
    notifyListeners();
  }

  static String _fileNameStem(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final stem = dot > 0 ? fileName.substring(0, dot) : fileName;
    return stem.trim().isEmpty ? fileName : stem.trim();
  }

  String exportToString() {
    if (_data == null) throw Exception('No data to export');
    return _parser.export(_data!);
  }

  /// Exports the current course as a Garmin TCX `<Course>` document.
  /// Waypoints are emitted as ordered `<CoursePoint>` blocks with
  /// synthesized monotonic times so Garmin Connect places aid stations
  /// at the correct km on out-and-back / lollipop routes — GPX `<wpt>`
  /// projection is ambiguous when a single lat/lon lies on the track
  /// at multiple cumulative distances.
  String exportTcxToString() {
    if (_data == null) throw Exception('No data to export');
    return _tcxExporter.export(data: _data!, tracks: visibleTracks);
  }

  /// Exports the current course as a Garmin FIT (binary) course file.
  /// FIT is Garmin Connect's native course format — unlike TCX, the
  /// Courses → Import path on Connect preserves every `course_point`
  /// message, so aid stations land at the right km on both forward
  /// and return passes of out-and-back routes.
  Uint8List exportFitToBytes() {
    if (_data == null) throw Exception('No data to export');
    return _fitExporter.export(data: _data!, tracks: visibleTracks);
  }

  void createNew() {
    _data = GpxData(
      name: 'New Route',
      tracks: [
        GpxTrack(name: 'Track 1', segments: [GpxTrackSegment()]),
      ],
    );
    _fileName = 'new_route.gpx';
    _editMode = EditMode.view;
    _selectedPointId = null;
    _notifyProfileChanged();
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
      tracks.add(GpxTrack(name: 'Track 1', segments: [GpxTrackSegment()]));
    }
    final segment = tracks.first.segments.first;
    final point = GpxTrackPoint(latLng: latLng);
    if (index != null && index <= segment.points.length) {
      segment.points.insert(index, point);
    } else {
      segment.points.add(point);
    }
    _data = _data!.copyWith(tracks: tracks);
    _notifyProfileChanged();
  }

  void removeTrackPoint(String id) {
    if (_data == null) return;
    for (final track in _data!.tracks) {
      for (final seg in track.segments) {
        seg.points.removeWhere((p) => p.id == id);
      }
    }
    if (_selectedPointId == id) _selectedPointId = null;
    _notifyProfileChanged();
  }

  void moveTrackPoint(String id, LatLng newLatLng) {
    if (_data == null) return;
    for (final track in _data!.tracks) {
      for (final seg in track.segments) {
        final idx = seg.points.indexWhere((p) => p.id == id);
        if (idx != -1) {
          seg.points[idx] = seg.points[idx].copyWith(latLng: newLatLng);
          _notifyProfileChanged();
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
    _notifyProfileChanged();
  }

  // Waypoint operations
  void addWaypoint(
    LatLng latLng, {
    String? name,
    WaypointType? type,
    String? cutoff,
  }) {
    if (_data == null) return;
    // Snap to nearest point on the track when the click lands within the
    // snap tolerance so the resulting GPX can be promoted to Garmin course
    // points on export. Also lift elevation from the track.
    final profile = elevationProfile();
    final nearest = profile.nearestOnTrack(latLng);
    LatLng resolved = latLng;
    double? elevation;
    double? trackDistance;
    if (nearest != null && nearest.distanceToLineMeters <= snapTolerance) {
      resolved = nearest.latLng;
      elevation = profile.sampleAtDistance(nearest.distance).elevation;
      trackDistance = nearest.distance;
    }
    final wpt = GpxWaypoint(
      latLng: resolved,
      elevation: elevation,
      name:
          name ??
          '${(type ?? _selectedWaypointType).label} ${_data!.waypoints.length + 1}',
      type: type ?? _selectedWaypointType,
      cutoff: cutoff,
      trackDistance: trackDistance,
    );
    _data!.waypoints.add(wpt);
    notifyListeners();
  }

  /// Adds a waypoint at the given cumulative distance along the track. Used
  /// by the "add by km" dialog when a runner has a list of aid stations
  /// keyed by distance from the race brief and doesn't want to hunt for
  /// each one on the map.
  void addWaypointAtDistance(
    double meters, {
    String? name,
    WaypointType? type,
    String? cutoff,
  }) {
    if (_data == null) return;
    final profile = elevationProfile();
    if (profile.isEmpty) return;
    final clamped = meters.clamp(0, profile.totalDistance).toDouble();
    final sample = profile.sampleAtDistance(clamped);
    final resolvedType = type ?? _selectedWaypointType;
    final wpt = GpxWaypoint(
      latLng: sample.latLng,
      elevation: sample.elevation,
      name: name ?? '${resolvedType.label} ${_data!.waypoints.length + 1}',
      type: resolvedType,
      cutoff: cutoff,
      trackDistance: clamped,
    );
    _data!.waypoints.add(wpt);
    notifyListeners();
  }

  /// Walks the climb detector over the current track and creates a Summit
  /// waypoint at the top of every detected climb that doesn't already have
  /// a waypoint within ~120 m. Returns the number of waypoints added.
  int autoWaypointsFromClimbs() {
    if (_data == null) return 0;
    final profile = elevationProfile();
    if (profile.isEmpty || !profile.hasElevation) return 0;
    final climbs = ClimbDetector.detect(profile);
    if (climbs.isEmpty) return 0;

    int added = 0;
    int counter = 1;
    for (final climb in climbs) {
      final sample = profile.sampleAtDistance(climb.endDistance);
      final dup = _data!.waypoints.any((w) {
        final d = GeoUtils.distanceBetween(w.latLng, sample.latLng);
        return d < snapTolerance;
      });
      if (dup) continue;
      _data!.waypoints.add(
        GpxWaypoint(
          latLng: sample.latLng,
          elevation: sample.elevation,
          name: 'Summit $counter (+${climb.gain.round()} m)',
          type: WaypointType.summit,
          trackDistance: climb.endDistance,
        ),
      );
      added++;
      counter++;
    }
    if (added > 0) notifyListeners();
    return added;
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
            trackDistance: nearest.distance,
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
      trackDistance: nearest.distance,
    );
    _invalidateWaypointProjection(id);
    notifyListeners();
  }

  /// Projects [wpt] onto the current track and returns the cumulative
  /// distance (meters) and perpendicular offset, or null if there is no
  /// track to project onto. Used by the sidebar and elevation chart to
  /// show "km from start" / off-track warnings.
  WaypointTrackInfo? waypointTrackInfo(GpxWaypoint wpt) {
    final nearest = nearestOnTrackForWaypoint(wpt);
    if (nearest == null) return null;
    // Prefer the stored track distance — it's authoritative on out-and-
    // back / lollipop routes where a single lat/lon lies on the track at
    // multiple km values. Projection is only used to compute the
    // perpendicular offset (off-track warning).
    final distance = wpt.trackDistance ?? nearest.distance;
    return WaypointTrackInfo(
      distance: distance,
      offsetMeters: nearest.distanceToLineMeters,
      onTrack: nearest.distanceToLineMeters <= snapTolerance,
    );
  }

  void removeWaypoint(String id) {
    if (_data == null) return;
    _data!.waypoints.removeWhere((w) => w.id == id);
    if (_selectedPointId == id) _selectedPointId = null;
    _invalidateWaypointProjection(id);
    notifyListeners();
  }

  void updateWaypoint(
    String id, {
    String? name,
    String? description,
    WaypointType? type,
    LatLng? latLng,
    String? cutoff,
    bool clearCutoff = false,
  }) {
    if (_data == null) return;
    final idx = _data!.waypoints.indexWhere((w) => w.id == id);
    if (idx == -1) return;
    _data!.waypoints[idx] = _data!.waypoints[idx].copyWith(
      name: name,
      description: description,
      type: type,
      latLng: latLng,
      cutoff: cutoff,
      clearCutoff: clearCutoff,
      // Free-form lat/lon change invalidates the stored along-track
      // distance — projection takes over again.
      clearTrackDistance: latLng != null,
    );
    if (latLng != null) _invalidateWaypointProjection(id);
    notifyListeners();
  }

  void moveWaypoint(String id, LatLng newLatLng) {
    if (_data == null) return;
    final idx = _data!.waypoints.indexWhere((w) => w.id == id);
    if (idx != -1) {
      _data!.waypoints[idx] = _data!.waypoints[idx].copyWith(
        latLng: newLatLng,
        clearTrackDistance: true,
      );
      _invalidateWaypointProjection(id);
      notifyListeners();
    }
  }

  /// Slides an existing waypoint along the track to the given cumulative
  /// distance (meters), updating its lat/lng and elevation from the track
  /// sample. No-op when there's no track to project onto.
  void moveWaypointToDistance(String id, double meters) {
    if (_data == null) return;
    final idx = _data!.waypoints.indexWhere((w) => w.id == id);
    if (idx == -1) return;
    final profile = elevationProfile();
    if (profile.isEmpty) return;
    final clamped = meters.clamp(0, profile.totalDistance).toDouble();
    final sample = profile.sampleAtDistance(clamped);
    _data!.waypoints[idx] = _data!.waypoints[idx].copyWith(
      latLng: sample.latLng,
      elevation: sample.elevation,
      trackDistance: clamped,
    );
    _invalidateWaypointProjection(id);
    notifyListeners();
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
    _notifyProfileChanged();
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
      final mid = LatLng(
        (a.latitude + b.latitude) / 2,
        (a.longitude + b.longitude) / 2,
      );
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
