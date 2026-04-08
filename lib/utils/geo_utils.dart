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

  static double totalElevationGain(List<GpxTrackPoint> points) {
    double gain = 0;
    for (int i = 1; i < points.length; i++) {
      final prev = points[i - 1].elevation;
      final curr = points[i].elevation;
      if (prev != null && curr != null && curr > prev) {
        gain += curr - prev;
      }
    }
    return gain;
  }

  static double totalElevationLoss(List<GpxTrackPoint> points) {
    double loss = 0;
    for (int i = 1; i < points.length; i++) {
      final prev = points[i - 1].elevation;
      final curr = points[i].elevation;
      if (prev != null && curr != null && curr < prev) {
        loss += prev - curr;
      }
    }
    return loss;
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
}
