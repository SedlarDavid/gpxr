import '../models/gpx_models.dart';
import 'elevation_profile.dart';

/// A sustained descent detected on an [ElevationProfile]. Mirror of
/// [Climb] but oriented downhill — used by trail runners to gauge knee
/// impact (eccentric quad load) and by cyclists to flag long sustained
/// drops where brake-cooling discipline matters.
class Descent {
  Descent({
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

  /// Maximum sustained descent grade (positive fraction) over a sliding
  /// window inside the descent.
  final double maxGrade;

  double get length => endDistance - startDistance;

  /// Total elevation drop in meters, always positive.
  double get loss => startElevation - endElevation;

  /// Average descent grade across the whole segment as a positive
  /// fraction (0.08 = -8%).
  double get averageGrade => length > 0 ? loss / length : 0;

  /// FIETS-inspired severity score, repurposed for descents. The same
  /// formula (H² / (L × 10)) ranks descents by how brutal they are: a
  /// sharp drop in a short distance scores higher than the same drop
  /// spread out — which matches what the legs actually feel.
  double get severityScore {
    if (length <= 0) return 0;
    return (loss * loss) / (length * 10);
  }

  /// Cycling-style category derived from [severityScore]. Mirrors the
  /// climb cat ladder so a route's "Cat 2 climb followed by a Cat 2
  /// descent" reads consistently in the UI.
  DescentCategory get bikeCategory {
    final s = severityScore;
    if (s >= 8) return DescentCategory.hc;
    if (s >= 5) return DescentCategory.cat1;
    if (s >= 3) return DescentCategory.cat2;
    if (s >= 1.5) return DescentCategory.cat3;
    return DescentCategory.cat4;
  }

  /// Trail-runner knee-impact category. Tuned slightly tighter than the
  /// climb ladder because descents tend to do more damage per vertical
  /// meter than climbs of the same size — eccentric quad load and
  /// braking on technical ground are the limiting factor in long ultras.
  DescentCategory get trailCategory {
    final l = loss;
    final pct = averageGrade * 100;
    if (l >= 700 || (l >= 400 && pct >= 12)) return DescentCategory.brutal;
    if (l >= 350 || (l >= 220 && pct >= 12)) return DescentCategory.veryHard;
    if (l >= 180 || (l >= 100 && pct >= 10)) return DescentCategory.hard;
    if (l >= 70) return DescentCategory.moderate;
    return DescentCategory.easy;
  }

  DescentCategory categoryFor(ActivityType activity) {
    switch (activity) {
      case ActivityType.bike:
        return bikeCategory;
      case ActivityType.trailRun:
        return trailCategory;
    }
  }
}

enum DescentCategory {
  cat4('Cat 4'),
  cat3('Cat 3'),
  cat2('Cat 2'),
  cat1('Cat 1'),
  hc('HC'),
  easy('Easy'),
  moderate('Moderate'),
  hard('Hard'),
  veryHard('Very hard'),
  brutal('Brutal');

  const DescentCategory(this.label);
  final String label;
}

/// Finds sustained descents on an elevation profile. Mirror of
/// [ClimbDetector] — same hysteresis state machine, but watching for
/// drops instead of rises so undulating singletrack doesn't get split
/// into a dozen micro-descents.
class DescentDetector {
  /// Returns all descents along [profile] meeting [minLoss] and
  /// [minLength]. [noiseThreshold] is how far elevation must rise from
  /// a running low before we consider the descent finished.
  static List<Descent> detect(
    ElevationProfile profile, {
    double minLoss = 30.0,
    double minLength = 300.0,
    double noiseThreshold = 10.0,
  }) {
    if (profile.isEmpty || !profile.hasElevation) return const [];

    final descents = <Descent>[];

    double? highEle;
    int highIdx = 0;

    bool inDescent = false;
    int descentStartIdx = 0;
    double descentStartEle = 0;
    int troughIdx = 0;
    double troughEle = double.infinity;

    for (int i = 0; i < profile.length; i++) {
      final e = profile.elevations[i];
      if (e == null) continue;

      if (!inDescent) {
        if (highEle == null || e >= highEle) {
          highEle = e;
          highIdx = i;
          continue;
        }
        if (highEle - e >= noiseThreshold) {
          inDescent = true;
          descentStartIdx = highIdx;
          descentStartEle = highEle;
          troughIdx = i;
          troughEle = e;
        }
      } else {
        if (e <= troughEle) {
          troughIdx = i;
          troughEle = e;
          continue;
        }
        if (e - troughEle >= noiseThreshold) {
          final descent = _buildDescent(
            profile,
            descentStartIdx,
            troughIdx,
            descentStartEle,
            troughEle,
          );
          if (descent.loss >= minLoss && descent.length >= minLength) {
            descents.add(descent);
          }
          inDescent = false;
          highEle = e;
          highIdx = i;
        }
      }
    }

    if (inDescent) {
      final descent = _buildDescent(
        profile,
        descentStartIdx,
        troughIdx,
        descentStartEle,
        troughEle,
      );
      if (descent.loss >= minLoss && descent.length >= minLength) {
        descents.add(descent);
      }
    }

    return descents;
  }

  static Descent _buildDescent(
    ElevationProfile profile,
    int startIdx,
    int endIdx,
    double startEle,
    double endEle,
  ) {
    final startDist = profile.distances[startIdx];
    final endDist = profile.distances[endIdx];
    final maxGrade = _computeMaxGrade(profile, startIdx, endIdx);
    return Descent(
      startDistance: startDist,
      endDistance: endDist,
      startElevation: startEle,
      endElevation: endEle,
      startIndex: startIdx,
      endIndex: endIdx,
      maxGrade: maxGrade,
    );
  }

  /// Steepest sustained descent grade (positive fraction) inside
  /// [startIdx]..[endIdx], measured over sliding windows of at least
  /// [windowMeters] so a single noisy 5 m drop between two adjacent
  /// points doesn't register as a 40% wall.
  static double _computeMaxGrade(
    ElevationProfile profile,
    int startIdx,
    int endIdx, {
    double windowMeters = 100.0,
  }) {
    final dists = profile.distances;
    final eles = profile.elevations;
    final totalLen = dists[endIdx] - dists[startIdx];
    final overallDrop = (eles[startIdx] ?? 0) - (eles[endIdx] ?? 0);
    final overallGrade = totalLen > 0 ? overallDrop / totalLen : 0.0;
    if (totalLen <= windowMeters) return overallGrade;

    double maxGrade = overallGrade;
    int j = startIdx;
    for (int i = startIdx; i < endIdx; i++) {
      final eStart = eles[i];
      if (eStart == null) continue;
      while (j < endIdx && dists[j] - dists[i] < windowMeters) {
        j++;
      }
      if (j > endIdx) break;
      final eEnd = eles[j];
      if (eEnd == null) continue;
      final len = dists[j] - dists[i];
      if (len <= 0) continue;
      final grade = (eStart - eEnd) / len;
      if (grade > maxGrade) maxGrade = grade;
    }
    return maxGrade;
  }
}
