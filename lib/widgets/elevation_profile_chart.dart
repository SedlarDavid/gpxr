import 'package:flutter/material.dart';
import '../utils/elevation_profile.dart';
import '../utils/geo_utils.dart';
import '../utils/theme.dart';

/// Single waypoint marker rendered on the elevation profile chart.
class WaypointTick {
  const WaypointTick({
    required this.distance,
    required this.color,
    required this.icon,
    this.offTrack = false,
  });

  /// Cumulative distance (meters) along the track.
  final double distance;
  final Color color;
  /// Material icon drawn in a pill at the top of the tick so the user can
  /// recognise waypoint types at a glance on the elevation profile.
  final IconData icon;
  /// Renders as a hollow, dashed-style marker so users can tell off-track
  /// waypoints (e.g. a landmark placed beside the trail) from snapped ones.
  final bool offTrack;
}

class ElevationProfileChart extends StatelessWidget {
  const ElevationProfileChart({
    super.key,
    required this.profile,
    required this.hoverDistance,
    this.waypointTicks = const [],
    this.height = 96,
  });

  final ElevationProfile profile;
  final ValueNotifier<double?> hoverDistance;
  /// Ticks drawn along the baseline at each waypoint's cumulative distance,
  /// so the user can see at-a-glance where aid stations, peaks, etc. fall
  /// along the elevation profile.
  final List<WaypointTick> waypointTicks;
  final double height;

  static const double _padH = 8;
  static const double _padTop = 26;
  static const double _padBottom = 16;

  void _updateHover(double localX, double width) {
    if (profile.isEmpty || profile.totalDistance <= 0) return;
    final innerW = (width - _padH * 2).clamp(1.0, double.infinity);
    final x = (localX - _padH).clamp(0.0, innerW);
    hoverDistance.value = (x / innerW) * profile.totalDistance;
  }

  @override
  Widget build(BuildContext context) {
    if (profile.isEmpty || !profile.hasElevation) {
      return Container(
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          profile.isEmpty
              ? 'No track points'
              : 'No elevation data',
          style: TextStyle(
            fontSize: 11,
            color: AppTheme.textSecondary,
          ),
        ),
      );
    }

    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return MouseRegion(
            onHover: (e) => _updateHover(e.localPosition.dx, constraints.maxWidth),
            onExit: (_) => hoverDistance.value = null,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (d) => _updateHover(d.localPosition.dx, constraints.maxWidth),
              onPanUpdate: (d) => _updateHover(d.localPosition.dx, constraints.maxWidth),
              onPanEnd: (_) => hoverDistance.value = null,
              child: ValueListenableBuilder<double?>(
                valueListenable: hoverDistance,
                builder: (context, hoverD, _) {
                  return CustomPaint(
                    painter: _ElevationPainter(
                      profile: profile,
                      hoverDistance: hoverD,
                      waypointTicks: waypointTicks,
                      padH: _padH,
                      padTop: _padTop,
                      padBottom: _padBottom,
                    ),
                    size: Size.infinite,
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ElevationPainter extends CustomPainter {
  _ElevationPainter({
    required this.profile,
    required this.hoverDistance,
    required this.waypointTicks,
    required this.padH,
    required this.padTop,
    required this.padBottom,
  });

  final ElevationProfile profile;
  final double? hoverDistance;
  final List<WaypointTick> waypointTicks;
  final double padH;
  final double padTop;
  final double padBottom;

  @override
  void paint(Canvas canvas, Size size) {
    final innerW = size.width - padH * 2;
    final innerH = size.height - padTop - padBottom;
    if (innerW <= 0 || innerH <= 0) return;

    final minE = profile.minElevation;
    final maxE = profile.maxElevation;
    final eSpan = (maxE - minE).abs() < 1 ? 1.0 : (maxE - minE);
    final totalD = profile.totalDistance;
    if (totalD <= 0) return;

    double xFor(double d) => padH + (d / totalD) * innerW;
    double yFor(double e) =>
        padTop + innerH - ((e - minE) / eSpan) * innerH;

    // Baseline at the bottom of the inner area.
    final baselineY = padTop + innerH;

    // Build the path along the profile.
    final linePath = Path();
    final areaPath = Path();
    bool started = false;
    double? firstX;
    double? lastX;
    for (int i = 0; i < profile.length; i++) {
      final e = profile.elevations[i];
      if (e == null) continue;
      final x = xFor(profile.distances[i]);
      final y = yFor(e);
      if (!started) {
        linePath.moveTo(x, y);
        areaPath.moveTo(x, baselineY);
        areaPath.lineTo(x, y);
        firstX = x;
        started = true;
      } else {
        linePath.lineTo(x, y);
        areaPath.lineTo(x, y);
      }
      lastX = x;
    }
    if (started && lastX != null && firstX != null) {
      areaPath.lineTo(lastX, baselineY);
      areaPath.close();
    }

    // Fill gradient under the curve.
    final areaPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppTheme.primaryColor.withValues(alpha: 0.25),
          AppTheme.primaryColor.withValues(alpha: 0.03),
        ],
      ).createShader(Rect.fromLTWH(0, padTop, size.width, innerH));
    canvas.drawPath(areaPath, areaPaint);

    // Curve.
    final linePaint = Paint()
      ..color = AppTheme.primaryColor
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(linePath, linePaint);

    // Baseline.
    final axisPaint = Paint()
      ..color = AppTheme.borderColor
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(padH, baselineY),
      Offset(size.width - padH, baselineY),
      axisPaint,
    );

    // Min/max elevation labels (left side).
    _drawLabel(
      canvas,
      '${profile.maxElevation.round()} m',
      Offset(padH, padTop - 14),
      Alignment.topLeft,
    );
    _drawLabel(
      canvas,
      '${profile.minElevation.round()} m',
      Offset(padH, baselineY + 2),
      Alignment.topLeft,
    );

    // Distance label (right side).
    _drawLabel(
      canvas,
      GeoUtils.formatDistance(totalD),
      Offset(size.width - padH, baselineY + 2),
      Alignment.topRight,
    );

    // Waypoint ticks: a faint vertical line drops from the waypoint's
    // icon pill down to the baseline so users can link "this icon sits
    // at that distance/elevation" at a glance.
    const iconSize = 12.0;
    const pillR = 4.0;
    final pillH = iconSize + 4;
    for (final tick in waypointTicks) {
      if (tick.distance < 0 || tick.distance > totalD) continue;
      final tx = xFor(tick.distance);
      final pillTop = 1.0;
      final pillBottom = pillTop + pillH;
      final tickPaint = Paint()
        ..color = tick.color.withValues(alpha: 0.45)
        ..strokeWidth = 1;
      canvas.drawLine(
        Offset(tx, pillBottom),
        Offset(tx, baselineY),
        tickPaint,
      );

      // Icon pill at the top of the tick.
      final pillRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(tx - pillH / 2, pillTop, pillH, pillH),
        const Radius.circular(pillR),
      );
      if (tick.offTrack) {
        canvas.drawRRect(
          pillRect,
          Paint()..color = Colors.white,
        );
        canvas.drawRRect(
          pillRect,
          Paint()
            ..color = tick.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
      } else {
        canvas.drawRRect(pillRect, Paint()..color = tick.color);
      }
      _drawIcon(
        canvas,
        tick.icon,
        Offset(tx, pillTop + pillH / 2),
        iconSize,
        tick.offTrack ? tick.color : Colors.white,
      );
    }

    // Hover indicator.
    if (hoverDistance != null) {
      final sample = profile.sampleAtDistance(hoverDistance!);
      final hx = xFor(sample.distance);
      final hy = sample.elevation != null
          ? yFor(sample.elevation!)
          : baselineY;

      final vLinePaint = Paint()
        ..color = AppTheme.primaryColor.withValues(alpha: 0.55)
        ..strokeWidth = 1;
      canvas.drawLine(
        Offset(hx, padTop),
        Offset(hx, baselineY),
        vLinePaint,
      );

      // Dot.
      final dotFill = Paint()..color = AppTheme.primaryColor;
      final dotStroke = Paint()
        ..color = Colors.white
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(Offset(hx, hy), 4, dotFill);
      canvas.drawCircle(Offset(hx, hy), 4, dotStroke);

      // Tooltip label above.
      final label = StringBuffer(GeoUtils.formatDistance(sample.distance));
      if (sample.elevation != null) {
        label.write('  ·  ${sample.elevation!.round()} m');
      }
      _drawPill(canvas, size, label.toString(), hx);
    }
  }

  void _drawLabel(Canvas canvas, String text, Offset anchor, Alignment align) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 10,
          color: AppTheme.textSecondary,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = align == Alignment.topRight ? anchor.dx - tp.width : anchor.dx;
    tp.paint(canvas, Offset(dx, anchor.dy));
  }

  void _drawIcon(
    Canvas canvas,
    IconData icon,
    Offset center,
    double size,
    Color color,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: size,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(center.dx - tp.width / 2, center.dy - tp.height / 2),
    );
  }

  void _drawPill(Canvas canvas, Size size, String text, double x) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: 10,
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    const padX = 6.0;
    const padY = 3.0;
    final w = tp.width + padX * 2;
    final h = tp.height + padY * 2;
    double left = x - w / 2;
    if (left < 2) left = 2;
    if (left + w > size.width - 2) left = size.width - 2 - w;
    final rect = Rect.fromLTWH(left, 0, w, h);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));
    canvas.drawRRect(rrect, Paint()..color = AppTheme.primaryColor);
    tp.paint(canvas, Offset(left + padX, padY));
  }

  @override
  bool shouldRepaint(covariant _ElevationPainter oldDelegate) {
    return oldDelegate.profile != profile ||
        oldDelegate.hoverDistance != hoverDistance ||
        !_ticksEqual(oldDelegate.waypointTicks, waypointTicks);
  }

  static bool _ticksEqual(List<WaypointTick> a, List<WaypointTick> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].distance != b[i].distance ||
          a[i].color != b[i].color ||
          a[i].icon != b[i].icon ||
          a[i].offTrack != b[i].offTrack) {
        return false;
      }
    }
    return true;
  }
}
