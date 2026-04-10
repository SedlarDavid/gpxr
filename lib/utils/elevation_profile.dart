import 'package:latlong2/latlong.dart';
import '../models/gpx_models.dart';
import 'geo_utils.dart';

/// Cumulative elevation / distance profile of a polyline.
class ElevationProfile {
  ElevationProfile._({
    required this.points,
    required this.distances,
    required this.elevations,
    required this.totalDistance,
    required this.minElevation,
    required this.maxElevation,
    required this.hasElevation,
  });

  final List<GpxTrackPoint> points;
  // Cumulative distance in meters at each index (same length as [points]).
  final List<double> distances;
  final List<double?> elevations;
  final double totalDistance;
  final double minElevation;
  final double maxElevation;
  final bool hasElevation;

  bool get isEmpty => points.isEmpty;
  int get length => points.length;

  static final ElevationProfile empty = ElevationProfile._(
    points: const [],
    distances: const [],
    elevations: const [],
    totalDistance: 0,
    minElevation: 0,
    maxElevation: 0,
    hasElevation: false,
  );

  static ElevationProfile fromPoints(List<GpxTrackPoint> pts) {
    if (pts.isEmpty) return empty;

    final distances = List<double>.filled(pts.length, 0);
    double total = 0;
    for (int i = 1; i < pts.length; i++) {
      total += GeoUtils.distanceBetween(pts[i - 1].latLng, pts[i].latLng);
      distances[i] = total;
    }

    final elevations = pts.map((p) => p.elevation).toList();
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
      points: pts,
      distances: distances,
      elevations: elevations,
      totalDistance: total,
      minElevation: minEle,
      maxElevation: maxEle,
      hasElevation: hasEle,
    );
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
