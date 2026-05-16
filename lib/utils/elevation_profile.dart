import 'dart:math';

import 'package:latlong2/latlong.dart';
import '../models/gpx_models.dart';
import 'geo_utils.dart';

/// Cumulative elevation / distance profile of a polyline.
///
/// When built from multiple tracks (via [fromSegments]) the profile
/// records [segmentStarts] — the indices that begin a new track. The
/// haversine distance between the end of one track and the start of
/// the next is *not* added to the cumulative distance (otherwise
/// merging four geographically separate tracks would inflate total
/// distance by hundreds of km of phantom inter-track jumps), and
/// climb/descent detectors treat those indices as hard breaks.
class ElevationProfile {
  ElevationProfile._({
    required this.points,
    required this.distances,
    required this.elevations,
    required this.totalDistance,
    required this.minElevation,
    required this.maxElevation,
    required this.hasElevation,
    required this.segmentStarts,
  });

  final List<GpxTrackPoint> points;
  // Cumulative distance in meters at each index (same length as [points]).
  final List<double> distances;
  final List<double?> elevations;
  final double totalDistance;
  final double minElevation;
  final double maxElevation;
  final bool hasElevation;

  /// Indices at which a new sub-track begins. Always contains 0 (when
  /// the profile is non-empty). For a single-track profile this is
  /// just `[0]`. Used by the climb/descent detectors to reset state at
  /// boundaries and by the profile chart to render visual breaks.
  final List<int> segmentStarts;

  bool get isEmpty => points.isEmpty;
  int get length => points.length;

  /// True when [segmentStarts] indicates [index] is the first point of
  /// a new sub-track (other than the very first point of the profile).
  bool isSegmentBreakBefore(int index) =>
      index > 0 && segmentStarts.contains(index);

  static final ElevationProfile empty = ElevationProfile._(
    points: const [],
    distances: const [],
    elevations: const [],
    totalDistance: 0,
    minElevation: 0,
    maxElevation: 0,
    hasElevation: false,
    segmentStarts: const [],
  );

  static ElevationProfile fromPoints(List<GpxTrackPoint> pts) =>
      fromSegments([pts]);

  /// Builds a profile from a list of tracks (or any list of point
  /// runs). Distance accumulates within each run but does *not* span
  /// the gap between runs.
  static ElevationProfile fromSegments(List<List<GpxTrackPoint>> segments) {
    final flat = <GpxTrackPoint>[];
    final segStarts = <int>[];
    for (final seg in segments) {
      if (seg.isEmpty) continue;
      segStarts.add(flat.length);
      flat.addAll(seg);
    }
    if (flat.isEmpty) return empty;

    final distances = List<double>.filled(flat.length, 0);
    double total = 0;
    final boundarySet = segStarts.toSet();
    for (int i = 1; i < flat.length; i++) {
      if (boundarySet.contains(i)) {
        // Crossing into a new sub-track — keep the cumulative distance
        // but skip the haversine jump to the previous track's last
        // point.
        distances[i] = total;
        continue;
      }
      total += GeoUtils.distanceBetween(flat[i - 1].latLng, flat[i].latLng);
      distances[i] = total;
    }

    final elevations = flat.map((p) => p.elevation).toList();
    double minEle = double.infinity;
    double maxEle = -double.infinity;
    bool hasEle = false;
    for (final e in elevations) {
      if (e == null) continue;
      hasEle = true;
      if (e < minEle) minEle = e;
      if (e > maxEle) maxEle = e;
    }
    if (!hasEle) {
      minEle = 0;
      maxEle = 0;
    }

    return ElevationProfile._(
      points: flat,
      distances: distances,
      elevations: elevations,
      totalDistance: total,
      minElevation: minEle,
      maxElevation: maxEle,
      hasElevation: hasEle,
      segmentStarts: List.unmodifiable(segStarts),
    );
  }

  /// Returns the index of the track point closest to cumulative
  /// distance [d]. Unlike [sampleAtDistance], which interpolates a
  /// fresh lat/lon between two adjacent points, this snaps to a real
  /// point that already exists in the polyline — useful for emitters
  /// (TCX course export) that need a Position/Time that exactly
  /// matches one of the existing Trackpoints, because Garmin's strict
  /// importer drops CoursePoints whose Time doesn't line up with a
  /// real Trackpoint.
  int nearestIndexForDistance(double d) {
    if (distances.isEmpty) return 0;
    final upper = _indexForDistance(d);
    if (upper == 0) return 0;
    final lower = upper - 1;
    return (d - distances[lower]) < (distances[upper] - d) ? lower : upper;
  }

  /// Returns the upper-bound index i such that distances[i] >= d.
  int _indexForDistance(double d) {
    if (distances.isEmpty) return 0;
    if (d <= 0) return 0;
    if (d >= totalDistance) return distances.length - 1;
    int lo = 0;
    int hi = distances.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (distances[mid] < d) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Projects [p] onto the closest segment of the polyline and returns the
  /// snapped position, its cumulative distance along the profile, and the
  /// perpendicular distance (in meters) from [p] to the line.
  ///
  /// Uses a local equirectangular approximation anchored at [p]'s latitude
  /// so the projection math is done in a metric plane — accurate enough for
  /// snap tolerances up to several kilometers.
  NearestOnTrack? nearestOnTrack(LatLng p) {
    if (points.isEmpty) return null;
    if (points.length == 1) {
      return NearestOnTrack(
        distance: 0,
        latLng: points.first.latLng,
        distanceToLineMeters: GeoUtils.distanceBetween(p, points.first.latLng),
        segmentIndex: 0,
        t: 0,
      );
    }

    final latRad = p.latitude * pi / 180;
    final mPerDegLat = 111320.0;
    final mPerDegLng = 111320.0 * cos(latRad);

    double bestSq = double.infinity;
    int bestSeg = 0;
    double bestT = 0;
    double bestPx = 0;
    double bestPy = 0;

    double projX(double lng) => (lng - p.longitude) * mPerDegLng;
    double projY(double lat) => (lat - p.latitude) * mPerDegLat;

    final boundary = segmentStarts.toSet();
    for (int i = 0; i < points.length - 1; i++) {
      // Skip the virtual segment that would otherwise span a track
      // boundary — there is no real polyline between the end of one
      // track and the start of the next.
      if (boundary.contains(i + 1)) continue;
      final ax = projX(points[i].latLng.longitude);
      final ay = projY(points[i].latLng.latitude);
      final bx = projX(points[i + 1].latLng.longitude);
      final by = projY(points[i + 1].latLng.latitude);
      final dx = bx - ax;
      final dy = by - ay;
      final lenSq = dx * dx + dy * dy;
      double t;
      if (lenSq == 0) {
        t = 0;
      } else {
        // Projection of the origin (p itself) onto the segment a→b.
        t = -(ax * dx + ay * dy) / lenSq;
        if (t < 0) t = 0;
        if (t > 1) t = 1;
      }
      final px = ax + t * dx;
      final py = ay + t * dy;
      final sq = px * px + py * py;
      if (sq < bestSq) {
        bestSq = sq;
        bestSeg = i;
        bestT = t;
        bestPx = px;
        bestPy = py;
      }
    }

    final cumA = distances[bestSeg];
    final cumB = distances[bestSeg + 1];
    final cumD = cumA + bestT * (cumB - cumA);

    final snapLat = p.latitude + bestPy / mPerDegLat;
    final snapLng = p.longitude + bestPx / mPerDegLng;

    return NearestOnTrack(
      distance: cumD,
      latLng: LatLng(snapLat, snapLng),
      distanceToLineMeters: sqrt(bestSq),
      segmentIndex: bestSeg,
      t: bestT,
    );
  }

  /// Interpolated sample at the given cumulative distance in meters.
  ProfileSample sampleAtDistance(double d) {
    if (points.isEmpty) {
      return ProfileSample(
        distance: 0,
        latLng: const LatLng(0, 0),
        elevation: null,
      );
    }
    final clamped = d.clamp(0, totalDistance).toDouble();
    final hi = _indexForDistance(clamped);
    if (hi == 0) {
      return ProfileSample(
        distance: distances[0],
        latLng: points[0].latLng,
        elevation: elevations[0],
      );
    }
    final lo = hi - 1;
    final segStart = distances[lo];
    final segEnd = distances[hi];
    final segLen = segEnd - segStart;
    final t = segLen > 0 ? (clamped - segStart) / segLen : 0.0;
    final aLat = points[lo].latLng.latitude;
    final bLat = points[hi].latLng.latitude;
    final aLng = points[lo].latLng.longitude;
    final bLng = points[hi].latLng.longitude;
    final aEle = elevations[lo];
    final bEle = elevations[hi];
    double? ele;
    if (aEle != null && bEle != null) {
      ele = aEle + (bEle - aEle) * t;
    } else {
      ele = aEle ?? bEle;
    }
    return ProfileSample(
      distance: clamped,
      latLng: LatLng(aLat + (bLat - aLat) * t, aLng + (bLng - aLng) * t),
      elevation: ele,
    );
  }
}

class ProfileSample {
  ProfileSample({
    required this.distance,
    required this.latLng,
    required this.elevation,
  });

  final double distance;
  final LatLng latLng;
  final double? elevation;
}

class NearestOnTrack {
  NearestOnTrack({
    required this.distance,
    required this.latLng,
    required this.distanceToLineMeters,
    required this.segmentIndex,
    required this.t,
  });

  /// Cumulative distance along the track of the projected point (meters).
  final double distance;

  /// Snapped position on the track polyline.
  final LatLng latLng;

  /// Perpendicular distance (meters) from the original point to the track.
  final double distanceToLineMeters;

  /// Index of the segment (point i → point i+1) the projection landed on.
  final int segmentIndex;

  /// Interpolation parameter along that segment in the range [0, 1].
  final double t;
}
