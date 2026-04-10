import 'dart:math';
import 'package:latlong2/latlong.dart';
import '../models/gpx_models.dart';

class GeoUtils {
  static const Distance _distance = Distance();

  static double totalDistance(List<LatLng> points) {
    if (points.length < 2) return 0;
    double total = 0;
    for (int i = 1; i < points.length; i++) {
      total += _distance.as(LengthUnit.Meter, points[i - 1], points[i]);
    }
    return total;
  }

  /// Minimum elevation change (meters) that counts as a real climb or
  /// descent. Smaller deltas are treated as GPS noise and discarded. 5m is
  /// roughly what Strava/Trace de Trail use for trail data — summing raw
  /// deltas on a recorded GPX over-reports gain by 20–40%.
  static const double _elevationNoiseThreshold = 5.0;

  /// Total ascent over [points], ignoring sub-[_elevationNoiseThreshold]
  /// wiggles via hysteresis: we track the most recent turning point and
  /// only flip direction (and commit the pending gain/loss) once the
  /// elevation has moved more than the threshold in the opposite
  /// direction. This matches what trail-running platforms report.
  static double totalElevationGain(List<GpxTrackPoint> points) {
    return _hysteresisElevation(points, gain: true);
  }

  static double totalElevationLoss(List<GpxTrackPoint> points) {
    return _hysteresisElevation(points, gain: false);
  }

  static double _hysteresisElevation(
    List<GpxTrackPoint> points, {
    required bool gain,
  }) {
    double total = 0;
    double? refEle; // last committed turning point
    double? extremeEle; // running max (when climbing) / min (when descending)
    int direction = 0; // 1 climbing, -1 descending, 0 unknown
    for (final p in points) {
      final e = p.elevation;
      if (e == null) continue;
      if (refEle == null) {
        refEle = e;
        extremeEle = e;
        continue;
      }
      if (direction == 1) {
        if (e >= extremeEle!) {
          extremeEle = e;
        } else if (extremeEle - e >= _elevationNoiseThreshold) {
          // Confirmed reversal: commit the climb, start tracking descent.
          if (gain) total += extremeEle - refEle;
          refEle = extremeEle;
          extremeEle = e;
          direction = -1;
        }
      } else if (direction == -1) {
        if (e <= extremeEle!) {
          extremeEle = e;
        } else if (e - extremeEle >= _elevationNoiseThreshold) {
          if (!gain) total += refEle - extremeEle;
          refEle = extremeEle;
          extremeEle = e;
          direction = 1;
        }
      } else {
        // Direction not yet established — wait until we move more than
        // the threshold away from the starting reference.
        if (e - refEle >= _elevationNoiseThreshold) {
          direction = 1;
          extremeEle = e;
        } else if (refEle - e >= _elevationNoiseThreshold) {
          direction = -1;
          extremeEle = e;
        }
      }
    }
    // Commit the trailing leg so a track that ends mid-climb still counts.
    if (direction == 1 && extremeEle != null && refEle != null) {
      if (gain && extremeEle > refEle) total += extremeEle - refEle;
    } else if (direction == -1 && extremeEle != null && refEle != null) {
      if (!gain && extremeEle < refEle) total += refEle - extremeEle;
    }
    return total;
  }

  static LatLng center(List<LatLng> points) {
    if (points.isEmpty) return const LatLng(48.8566, 2.3522);
    double lat = 0, lon = 0;
    for (final p in points) {
      lat += p.latitude;
      lon += p.longitude;
    }
    return LatLng(lat / points.length, lon / points.length);
  }

  static double fitZoom(List<LatLng> points, {double maxZoom = 18}) {
    if (points.length < 2) return 14;
    double minLat = 90, maxLat = -90, minLon = 180, maxLon = -180;
    for (final p in points) {
      minLat = min(minLat, p.latitude);
      maxLat = max(maxLat, p.latitude);
      minLon = min(minLon, p.longitude);
      maxLon = max(maxLon, p.longitude);
    }
    final latDiff = maxLat - minLat;
    final lonDiff = maxLon - minLon;
    final maxDiff = max(latDiff, lonDiff);

    if (maxDiff < 0.001) return maxZoom;
    if (maxDiff < 0.01) return 15;
    if (maxDiff < 0.05) return 13;
    if (maxDiff < 0.1) return 12;
    if (maxDiff < 0.5) return 10;
    if (maxDiff < 1) return 9;
    if (maxDiff < 5) return 7;
    if (maxDiff < 10) return 5;
    return 3;
  }

  static String formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.round()} m';
    }
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  static String formatElevation(double meters) {
    return '${meters.round()} m';
  }

  static double distanceBetween(LatLng a, LatLng b) {
    return _distance.as(LengthUnit.Meter, a, b);
  }

  /// Returns the Mercator-projected direction angle (radians, 0 = up/north,
  /// clockwise positive) for the heading from [a] to [b]. Matches how the
  /// line appears on a Web Mercator map, so it's suitable for rotating
  /// arrow icons along a polyline.
  static double mercatorBearing(LatLng a, LatLng b) {
    final lat1 = a.latitude * pi / 180;
    final lat2 = b.latitude * pi / 180;
    final y1 = log(tan(pi / 4 + lat1 / 2));
    final y2 = log(tan(pi / 4 + lat2 / 2));
    final dx = b.longitude - a.longitude;
    final dy = y2 - y1;
    if (dx == 0 && dy == 0) return 0;
    return atan2(dx, dy);
  }
}
