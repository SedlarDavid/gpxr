import '../models/gpx_models.dart';
import 'elevation_profile.dart';

/// A sustained climb detected on an [ElevationProfile]. Start/end are
/// cumulative distances along the track in meters, elevations in meters.
class Climb {
  Climb({
    required this.startDistance,
    required this.endDistance,
    required this.startElevation,
    required this.endElevation,
    required this.startIndex,
    required this.endIndex,
    required this.maxGrade,
  });

  final double startDistance;
  final double endDistance;
  final double startElevation;
  final double endElevation;
  final int startIndex;
  final int endIndex;

  /// Maximum sustained grade (fraction, not percent) over a sliding window
  /// inside the climb. See [ClimbDetector._computeMaxGrade].
  final double maxGrade;

  double get length => endDistance - startDistance;
  double get gain => endElevation - startElevation;

  /// Average grade across the whole climb as a fraction (0.08 = 8%).
  double get averageGrade => length > 0 ? gain / length : 0;

  /// FIETS-inspired difficulty score:
  ///   fiets = (H^2 / (L * 10)) where H is gain (m), L is length (m).
  /// Used for rough categorization. The real FIETS formula also accounts
  /// for altitude, but this simplified version is enough to rank climbs
  /// within a single course.
  double get fietsScore {
    if (length <= 0) return 0;
    return (gain * gain) / (length * 10);
  }

  /// Cycling-style category derived from [fietsScore]. Used when the
  /// active activity is [ActivityType.bike].
  ClimbCategory get bikeCategory {
    final s = fietsScore;
    if (s >= 8) return ClimbCategory.hc;
    if (s >= 5) return ClimbCategory.cat1;
    if (s >= 3) return ClimbCategory.cat2;
    if (s >= 1.5) return ClimbCategory.cat3;
    return ClimbCategory.cat4;
  }

  /// Trail-runner-friendly category. Trail climbs are shorter and steeper
  /// than road climbs, so we lean on absolute vertical gain combined with
  /// average grade rather than the road-cycling FIETS thresholds.
  ClimbCategory get trailCategory {
    final g = gain;
    final pct = averageGrade * 100;
    if (g >= 800 || (g >= 500 && pct >= 12)) return ClimbCategory.brutal;
    if (g >= 400 || (g >= 250 && pct >= 12)) return ClimbCategory.veryHard;
    if (g >= 200 || (g >= 120 && pct >= 10)) return ClimbCategory.hard;
    if (g >= 80) return ClimbCategory.moderate;
    return ClimbCategory.easy;
  }

  ClimbCategory categoryFor(ActivityType activity) {
    switch (activity) {
      case ActivityType.bike:
        return bikeCategory;
      case ActivityType.trailRun:
        return trailCategory;
    }
  }
}

enum ClimbCategory {
  // Cycling categories.
  cat4('Cat 4'),
  cat3('Cat 3'),
  cat2('Cat 2'),
  cat1('Cat 1'),
  hc('HC'),
  // Trail-running categories.
  easy('Easy'),
  moderate('Moderate'),
  hard('Hard'),
  veryHard('Very hard'),
  brutal('Brutal');

  const ClimbCategory(this.label);
  final String label;
}

/// Finds sustained climbs on an elevation profile. Uses hysteresis on
/// elevation so GPS noise doesn't split one long ascent into dozens of
/// tiny ones.
class ClimbDetector {
  /// Returns all climbs along [profile] meeting [minGain] and [minLength].
  ///
  /// [noiseThreshold] is how far the elevation must drop from a running
  /// peak before we consider the climb finished — larger values merge
  /// short dips back into the parent climb (good for undulating ridges).
  static List<Climb> detect(
    ElevationProfile profile, {
    double minGain = 30.0,
    double minLength = 300.0,
    double noiseThreshold = 10.0,
  }) {
    if (profile.isEmpty || !profile.hasElevation) return const [];

    final climbs = <Climb>[];

    // State for the "searching for a climb start" phase.
    double? lowEle;
    int lowIdx = 0;

    // State for the "inside a climb" phase.
    bool inClimb = false;
    int climbStartIdx = 0;
    double climbStartEle = 0;
    int peakIdx = 0;
    double peakEle = -double.infinity;

    for (int i = 0; i < profile.length; i++) {
      final e = profile.elevations[i];
      if (e == null) continue;

      if (!inClimb) {
        if (lowEle == null || e <= lowEle) {
          lowEle = e;
          lowIdx = i;
          continue;
        }
        if (e - lowEle >= noiseThreshold) {
          // Confirmed rise from the last low — open a climb anchored at
          // that low, not at the current index, so we capture the full
          // ascent including the portion before the threshold was hit.
          inClimb = true;
          climbStartIdx = lowIdx;
          climbStartEle = lowEle;
          peakIdx = i;
          peakEle = e;
        }
      } else {
        if (e >= peakEle) {
          peakIdx = i;
          peakEle = e;
          continue;
        }
        if (peakEle - e >= noiseThreshold) {
          // Confirmed reversal — commit the climb (if big enough) and
          // start searching for the next one from the current point.
          final climb = _buildClimb(
            profile,
            climbStartIdx,
            peakIdx,
            climbStartEle,
            peakEle,
          );
          if (climb.gain >= minGain && climb.length >= minLength) {
            climbs.add(climb);
          }
          inClimb = false;
          lowEle = e;
          lowIdx = i;
        }
      }
    }

    // Trailing climb: track ended while we were still ascending.
    if (inClimb) {
      final climb = _buildClimb(
        profile,
        climbStartIdx,
        peakIdx,
        climbStartEle,
        peakEle,
      );
      if (climb.gain >= minGain && climb.length >= minLength) {
        climbs.add(climb);
      }
    }

    return climbs;
  }

  static Climb _buildClimb(
    ElevationProfile profile,
    int startIdx,
    int endIdx,
    double startEle,
    double endEle,
  ) {
    final startDist = profile.distances[startIdx];
    final endDist = profile.distances[endIdx];
    final maxGrade = _computeMaxGrade(profile, startIdx, endIdx);
    return Climb(
      startDistance: startDist,
      endDistance: endDist,
      startElevation: startEle,
      endElevation: endEle,
      startIndex: startIdx,
      endIndex: endIdx,
      maxGrade: maxGrade,
    );
  }

  /// Max sustained grade (as a fraction) inside [startIdx]..[endIdx],
  /// measured over sliding windows of at least [windowMeters] so a
  /// single noisy 5m jump between two points doesn't show up as a 40%
  /// wall. Falls back to the overall climb grade when the climb is
  /// shorter than the window.
  static double _computeMaxGrade(
    ElevationProfile profile,
    int startIdx,
    int endIdx, {
    double windowMeters = 100.0,
  }) {
    final dists = profile.distances;
    final eles = profile.elevations;
    final totalLen = dists[endIdx] - dists[startIdx];
    final overallRise = (eles[endIdx] ?? 0) - (eles[startIdx] ?? 0);
    final overallGrade = totalLen > 0 ? overallRise / totalLen : 0.0;
    if (totalLen <= windowMeters) return overallGrade;

    double maxGrade = overallGrade;
    int j = startIdx;
    for (int i = startIdx; i < endIdx; i++) {
      final eStart = eles[i];
      if (eStart == null) continue;
      // Advance j until the window is at least windowMeters long.
      while (j < endIdx && dists[j] - dists[i] < windowMeters) {
        j++;
      }
      if (j > endIdx) break;
      final eEnd = eles[j];
      if (eEnd == null) continue;
      final len = dists[j] - dists[i];
      if (len <= 0) continue;
      final grade = (eEnd - eStart) / len;
      if (grade > maxGrade) maxGrade = grade;
    }
    return maxGrade;
  }
}
