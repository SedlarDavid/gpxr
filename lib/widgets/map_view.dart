import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/gpx_models.dart';
import '../providers/gpx_provider.dart';
import '../utils/elevation_profile.dart';
import '../utils/geo_utils.dart';
import '../utils/theme.dart';
import '../utils/waypoint_icons.dart';

class MapView extends StatefulWidget {
  const MapView({super.key});

  @override
  State<MapView> createState() => _MapViewState();
}

enum _MapLayer { standard, outdoor }

class _MapViewState extends State<MapView> {
  static const String _mapyApiKey =
      String.fromEnvironment('MAPY_API_KEY');
  static bool get _hasMapyKey => _mapyApiKey.isNotEmpty;

  final MapController _mapController = MapController();
  String? _draggingPointId;
  bool _isDraggingWaypoint = false;
  String? _lastFittedFileName;
  final ValueNotifier<Offset?> _hoverCursor = ValueNotifier(null);
  late _MapLayer _layer;

  // Cached projection of track points into screen space for hover hit-
  // testing. Rebuilt only when the camera or the profile changes, not on
  // every mouse move — critical for large (50km+) tracks where calling
  // latLngToScreenPoint on every point every frame was making hover
  // completely unresponsive.
  Float64List? _screenXs;
  Float64List? _screenYs;
  ElevationProfile? _screenCacheProfile;
  double? _screenCacheZoom;
  LatLng? _screenCacheCenter;
  double? _screenCacheRotation;

  @override
  void initState() {
    super.initState();
    _layer = _hasMapyKey ? _MapLayer.outdoor : _MapLayer.standard;
  }

  @override
  void dispose() {
    _hoverCursor.dispose();
    _mapController.dispose();
    super.dispose();
  }

  String get _tileUrlTemplate {
    switch (_layer) {
      case _MapLayer.standard:
        return 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png';
      case _MapLayer.outdoor:
        return 'https://api.mapy.com/v1/maptiles/outdoor/256/{z}/{x}/{y}?apikey=$_mapyApiKey';
    }
  }

  List<String> get _tileSubdomains {
    switch (_layer) {
      case _MapLayer.standard:
        return const ['a', 'b', 'c'];
      case _MapLayer.outdoor:
        return const [];
    }
  }

  double get _tileMaxZoom {
    switch (_layer) {
      case _MapLayer.standard:
        return 17;
      case _MapLayer.outdoor:
        return 19;
    }
  }

  String get _attributionText {
    switch (_layer) {
      case _MapLayer.standard:
        return 'Map: © OpenTopoMap (CC-BY-SA) • Data: © OpenStreetMap contributors';
      case _MapLayer.outdoor:
        return '© Seznam.cz, a.s. • Mapy.com';
    }
  }

  void _invalidateScreenCache() {
    _screenXs = null;
    _screenYs = null;
    _screenCacheProfile = null;
    _screenCacheZoom = null;
    _screenCacheCenter = null;
    _screenCacheRotation = null;
  }

  void _ensureScreenCache(ElevationProfile profile) {
    final camera = _mapController.camera;
    final cacheValid = _screenXs != null &&
        identical(_screenCacheProfile, profile) &&
        _screenCacheZoom == camera.zoom &&
        _screenCacheCenter == camera.center &&
        _screenCacheRotation == camera.rotation;
    if (cacheValid) return;

    final n = profile.length;
    final xs = Float64List(n);
    final ys = Float64List(n);
    for (int i = 0; i < n; i++) {
      final p = camera.latLngToScreenPoint(profile.points[i].latLng);
      xs[i] = p.x.toDouble();
      ys[i] = p.y.toDouble();
    }
    _screenXs = xs;
    _screenYs = ys;
    _screenCacheProfile = profile;
    _screenCacheZoom = camera.zoom;
    _screenCacheCenter = camera.center;
    _screenCacheRotation = camera.rotation;
  }

  void _updateHoverFromCursor(
    Offset local,
    ElevationProfile profile,
    GpxProvider provider,
  ) {
    if (profile.isEmpty || profile.length < 2) {
      _hoverCursor.value = null;
      if (provider.hoverDistance.value != null) {
        provider.hoverDistance.value = null;
      }
      return;
    }

    _ensureScreenCache(profile);
    final xs = _screenXs!;
    final ys = _screenYs!;

    const threshold = 24.0;
    const thresholdSq = threshold * threshold;
    final cx = local.dx;
    final cy = local.dy;

    double bestSq = double.infinity;
    int bestSeg = 0;
    double bestT = 0;
    final last = xs.length - 1;
    for (int i = 0; i < last; i++) {
      final ax = xs[i];
      final ay = ys[i];
      final bx = xs[i + 1];
      final by = ys[i + 1];
      // Cheap axis-aligned bounding box reject so off-screen / far
      // segments never touch the projection math.
      final minX = ax < bx ? ax : bx;
      final maxX = ax < bx ? bx : ax;
      if (cx < minX - threshold || cx > maxX + threshold) continue;
      final minY = ay < by ? ay : by;
      final maxY = ay < by ? by : ay;
      if (cy < minY - threshold || cy > maxY + threshold) continue;

      final dx = bx - ax;
      final dy = by - ay;
      final lenSq = dx * dx + dy * dy;
      double t;
      if (lenSq == 0) {
        t = 0;
      } else {
        t = ((cx - ax) * dx + (cy - ay) * dy) / lenSq;
        if (t < 0) t = 0;
        if (t > 1) t = 1;
      }
      final px = ax + t * dx;
      final py = ay + t * dy;
      final ddx = px - cx;
      final ddy = py - cy;
      final sq = ddx * ddx + ddy * ddy;
      if (sq < bestSq) {
        bestSq = sq;
        bestSeg = i;
        bestT = t;
      }
    }

    if (bestSq > thresholdSq) {
      _hoverCursor.value = null;
      if (provider.hoverDistance.value != null) {
        provider.hoverDistance.value = null;
      }
      return;
    }

    final dA = profile.distances[bestSeg];
    final dB = profile.distances[bestSeg + 1];
    final d = dA + bestT * (dB - dA);
    provider.hoverDistance.value = d;
    _hoverCursor.value = local;
  }

  void _clearHover(GpxProvider provider) {
    if (_hoverCursor.value != null) _hoverCursor.value = null;
    if (provider.hoverDistance.value != null) {
      provider.hoverDistance.value = null;
    }
  }

  void _fitBounds(GpxData data) {
    final allPoints = <LatLng>[
      ...data.allLinePoints,
      ...data.waypoints.map((w) => w.latLng),
    ];
    if (allPoints.isEmpty) return;

    _mapController.rotate(0);

    if (allPoints.length == 1) {
      _mapController.move(allPoints.first, 14);
      return;
    }

    final bounds = LatLngBounds.fromPoints(allPoints);
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(48),
        maxZoom: 17,
      ),
    );
  }

  void _zoomBy(double delta) {
    final camera = _mapController.camera;
    final newZoom = (camera.zoom + delta).clamp(3.0, 19.0);
    _mapController.move(camera.center, newZoom);
  }

  void _maybeAutoFit(GpxData? data, String? fileName) {
    if (data == null || fileName == null) {
      _lastFittedFileName = null;
      return;
    }
    if (fileName == _lastFittedFileName) return;
    _lastFittedFileName = fileName;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fitBounds(data);
    });
  }

  void _handleMapTap(TapPosition tapPosition, LatLng latLng) {
    final provider = context.read<GpxProvider>();
    switch (provider.editMode) {
      case EditMode.addPoint:
        provider.insertTrackPointSmart(latLng);
        break;
      case EditMode.addWaypoint:
        _showAddWaypointDialog(latLng);
        break;
      case EditMode.deletePoint:
      case EditMode.view:
        provider.selectPoint(null);
        break;
    }
  }

  void _showAddWaypointDialog(LatLng latLng) {
    final provider = context.read<GpxProvider>();
    final nameController = TextEditingController();
    WaypointType selectedType = provider.selectedWaypointType;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Add Waypoint', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'e.g. Aid Station 1',
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                Text('Type', style: Theme.of(ctx).textTheme.labelMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: WaypointType.values.map((type) {
                    final isSelected = type == selectedType;
                    return FilterChip(
                      selected: isSelected,
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            WaypointIcons.iconFor(type),
                            size: 16,
                            color: isSelected
                                ? WaypointIcons.colorFor(type)
                                : AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(type.label),
                        ],
                      ),
                      onSelected: (_) {
                        setDialogState(() => selectedType = type);
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.isEmpty
                    ? '${selectedType.label} ${provider.data!.waypoints.length + 1}'
                    : nameController.text;
                provider.addWaypoint(latLng, name: name, type: selectedType);
                Navigator.pop(ctx);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GpxProvider>(
      builder: (context, provider, _) {
        final data = provider.data;
        final allPoints = data?.allLinePoints ?? [];
        final cursorStyle = _cursorForMode(provider.editMode);
        _maybeAutoFit(data, provider.fileName);

        final trackPoints = data == null
            ? const <GpxTrackPoint>[]
            : data.tracks.expand((t) => t.allPoints).toList();
        final profile = ElevationProfile.fromPoints(trackPoints);
        final hoverEnabled = provider.editMode == EditMode.view &&
            profile.length >= 2;

        return MouseRegion(
          cursor: cursorStyle,
          onHover: hoverEnabled
              ? (e) => _updateHoverFromCursor(e.localPosition, profile, provider)
              : null,
          onExit: (_) => _clearHover(provider),
          child: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: allPoints.isNotEmpty
                      ? GeoUtils.center(allPoints)
                      : const LatLng(48.8566, 2.3522),
                  initialZoom: allPoints.isNotEmpty
                      ? GeoUtils.fitZoom(allPoints)
                      : 5,
                  onTap: _handleMapTap,
                  onPositionChanged: (_, _) {
                    _invalidateScreenCache();
                    _clearHover(provider);
                  },
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.drag |
                        InteractiveFlag.flingAnimation |
                        InteractiveFlag.pinchZoom |
                        InteractiveFlag.doubleTapZoom |
                        InteractiveFlag.scrollWheelZoom,
                    rotationThreshold: 20.0,
                  ),
                ),
                children: [
                  TileLayer(
                    key: ValueKey(_layer),
                    urlTemplate: _tileUrlTemplate,
                    subdomains: _tileSubdomains,
                    userAgentPackageName: 'com.gpxr.app',
                    maxZoom: _tileMaxZoom,
                    tileProvider: CancellableNetworkTileProvider(),
                  ),
                  if (data != null) ..._buildTrackLayers(data, provider),
                  if (data != null && profile.length >= 2)
                    _buildDirectionMarkers(profile),
                  if (data != null && profile.length >= 1)
                    _buildStartFinishMarkers(profile),
                  if (data != null && provider.showWaypoints)
                    _buildWaypointLayer(data, provider),
                  // Climb highlight (active when user hovers a climb tile).
                  ValueListenableBuilder<(double, double)?>(
                    valueListenable: provider.hoveredClimbRange,
                    builder: (context, range, _) {
                      if (range == null || profile.length < 2) {
                        return PolylineLayer(polylines: const <Polyline>[]);
                      }
                      final (start, end) = range;
                      final pts = _climbLatLngs(profile, start, end);
                      if (pts.length < 2) {
                        return PolylineLayer(polylines: const <Polyline>[]);
                      }
                      return PolylineLayer(
                        polylines: [
                          Polyline(
                            points: pts,
                            color: const Color(0xFFEF4444),
                            strokeWidth: 6,
                            borderColor: Colors.white,
                            borderStrokeWidth: 2,
                          ),
                        ],
                      );
                    },
                  ),
                  // Hover marker on the route.
                  ValueListenableBuilder<double?>(
                    valueListenable: provider.hoverDistance,
                    builder: (context, d, _) {
                      if (d == null || profile.isEmpty) {
                        return const MarkerLayer(markers: []);
                      }
                      final sample = profile.sampleAtDistance(d);
                      return MarkerLayer(
                        markers: [
                          Marker(
                            point: sample.latLng,
                            width: 18,
                            height: 18,
                            child: IgnorePointer(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 3,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.25),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
              // Hover tooltip following the cursor.
              ValueListenableBuilder<Offset?>(
                valueListenable: _hoverCursor,
                builder: (context, cursor, _) {
                  if (cursor == null) return const SizedBox.shrink();
                  return ValueListenableBuilder<double?>(
                    valueListenable: provider.hoverDistance,
                    builder: (context, d, _) {
                      if (d == null) return const SizedBox.shrink();
                      final sample = profile.sampleAtDistance(d);
                      return _HoverTooltip(
                        cursor: cursor,
                        distance: sample.distance,
                        elevation: sample.elevation,
                      );
                    },
                  );
                },
              ),
              // Attribution (bottom left)
              Positioned(
                left: 8,
                bottom: 8,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _attributionText,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ),
              ),
              // Map controls (bottom right)
              Positioned(
                right: 12,
                bottom: 12,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _LayerMenuButton(
                      current: _layer,
                      mapyEnabled: _hasMapyKey,
                      onChanged: (v) => setState(() => _layer = v),
                    ),
                    const SizedBox(height: 8),
                    if (data != null && allPoints.isNotEmpty) ...[
                      _MapButton(
                        icon: Icons.fit_screen_rounded,
                        tooltip: 'Fit to route',
                        onTap: () => _fitBounds(data),
                      ),
                      const SizedBox(height: 8),
                    ],
                    _MapButton(
                      icon: Icons.add_rounded,
                      tooltip: 'Zoom in',
                      onTap: () => _zoomBy(1),
                    ),
                    const SizedBox(height: 8),
                    _MapButton(
                      icon: Icons.remove_rounded,
                      tooltip: 'Zoom out',
                      onTap: () => _zoomBy(-1),
                    ),
                  ],
                ),
              ),
              // Edit mode indicator
              if (provider.editMode != EditMode.view)
                Positioned(
                  top: 12,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _iconForMode(provider.editMode),
                            size: 16,
                            color: AppTheme.primaryColor,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _labelForMode(provider.editMode),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () => provider.setEditMode(EditMode.view),
                            borderRadius: BorderRadius.circular(12),
                            child: const Padding(
                              padding: EdgeInsets.all(2),
                              child: Icon(Icons.close, size: 16),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDirectionMarkers(ElevationProfile profile) {
    const maxArrows = 14;
    const minSpacingMeters = 250.0;
    final total = profile.totalDistance;
    if (total < 150) return const MarkerLayer(markers: []);

    final spacing = math.max(total / (maxArrows + 1), minSpacingMeters);
    final markers = <Marker>[];
    double d = spacing;
    while (d < total) {
      final delta = math.min(10.0, total * 0.02);
      final before = profile.sampleAtDistance(math.max(0, d - delta));
      final after = profile.sampleAtDistance(math.min(total, d + delta));
      final angle = GeoUtils.mercatorBearing(before.latLng, after.latLng);
      final pos = profile.sampleAtDistance(d);
      markers.add(
        Marker(
          point: pos.latLng,
          width: 18,
          height: 18,
          alignment: Alignment.center,
          child: IgnorePointer(
            child: Transform.rotate(
              angle: angle,
              child: Icon(
                Icons.navigation_rounded,
                size: 16,
                color: AppTheme.trackColor.withValues(alpha: 0.9),
                shadows: const [
                  Shadow(color: Colors.white, blurRadius: 2),
                ],
              ),
            ),
          ),
        ),
      );
      d += spacing;
    }
    return MarkerLayer(markers: markers);
  }

  Widget _buildStartFinishMarkers(ElevationProfile profile) {
    final markers = <Marker>[];
    if (profile.points.isNotEmpty) {
      markers.add(
        Marker(
          point: profile.points.first.latLng,
          width: 28,
          height: 28,
          alignment: Alignment.center,
          child: IgnorePointer(
            child: _EndpointBadge(
              color: const Color(0xFF22C55E),
              icon: Icons.play_arrow_rounded,
              tooltip: 'Start',
            ),
          ),
        ),
      );
    }
    if (profile.points.length > 1) {
      markers.add(
        Marker(
          point: profile.points.last.latLng,
          width: 28,
          height: 28,
          alignment: Alignment.center,
          child: IgnorePointer(
            child: _EndpointBadge(
              color: const Color(0xFFEF4444),
              icon: Icons.flag_rounded,
              tooltip: 'Finish',
            ),
          ),
        ),
      );
    }
    return MarkerLayer(markers: markers);
  }

  List<Widget> _buildTrackLayers(GpxData data, GpxProvider provider) {
    final layers = <Widget>[];

    // Track polylines
    for (final track in data.tracks) {
      for (final seg in track.segments) {
        if (seg.points.length >= 2) {
          layers.add(
            PolylineLayer(
              polylines: [
                Polyline(
                  points: seg.points.map((p) => p.latLng).toList(),
                  color: AppTheme.trackColor,
                  strokeWidth: 4,
                ),
              ],
            ),
          );
        }
      }
    }

    // Route polylines
    for (final route in data.routes) {
      if (route.points.length >= 2) {
        layers.add(
          PolylineLayer(
            polylines: [
              Polyline(
                points: route.points.map((p) => p.latLng).toList(),
                color: AppTheme.trackColorAlt,
                strokeWidth: 4,
              ),
            ],
          ),
        );
      }
    }

    // Track points (when editing or toggled on)
    if (provider.showTrackPoints || provider.editMode != EditMode.view) {
      final markers = <Marker>[];
      for (final track in data.tracks) {
        for (final seg in track.segments) {
          for (final pt in seg.points) {
            final isSelected = pt.id == provider.selectedPointId;
            markers.add(
              Marker(
                point: pt.latLng,
                width: isSelected ? 18 : 12,
                height: isSelected ? 18 : 12,
                child: GestureDetector(
                  onTap: () {
                    if (provider.editMode == EditMode.deletePoint) {
                      provider.removeTrackPoint(pt.id);
                    } else {
                      provider.selectPoint(pt.id);
                    }
                  },
                  onPanStart: (_) {
                    _draggingPointId = pt.id;
                    _isDraggingWaypoint = false;
                  },
                  onPanUpdate: (details) {
                    if (_draggingPointId != null) {
                      final renderBox = context.findRenderObject() as RenderBox;
                      final localPos = renderBox.globalToLocal(details.globalPosition);
                      final point = _mapController.camera.pointToLatLng(
                        math.Point(localPos.dx, localPos.dy),
                      );
                      provider.moveTrackPoint(_draggingPointId!, point);
                    }
                  },
                  onPanEnd: (_) => _draggingPointId = null,
                  child: Container(
                    decoration: BoxDecoration(
                      color: provider.editMode == EditMode.deletePoint
                          ? const Color(0xFFEF4444)
                          : isSelected
                              ? AppTheme.primaryColor
                              : Colors.white,
                      border: Border.all(
                        color: provider.editMode == EditMode.deletePoint
                            ? const Color(0xFFEF4444)
                            : AppTheme.primaryColor,
                        width: 2,
                      ),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            );
          }
        }
      }
      if (markers.isNotEmpty) {
        layers.add(MarkerLayer(markers: markers));
      }
    }

    return layers;
  }

  Widget _buildWaypointLayer(GpxData data, GpxProvider provider) {
    // Waypoints imported from Trace de Trail (or manually placed) can share
    // identical coordinates — e.g. an aid station and a medical point at
    // the same location. Group by coordinate so we can render each extra
    // marker with a vertical pixel offset and keep them all clickable
    // instead of stacking invisibly on top of each other.
    final stackIndex = <String, int>{};
    final groupCount = <String, int>{};
    for (final wpt in data.waypoints) {
      final key = _coordKey(wpt.latLng);
      stackIndex[wpt.id] = groupCount[key] ?? 0;
      groupCount[key] = (groupCount[key] ?? 0) + 1;
    }
    // Vertical pixel distance between successive stacked icons. Icons
    // are 32 px tall; 30 lets them sit with a 2 px visual seam so the
    // stack reads as one vertical strip instead of a ladder with gaps.
    const stackStep = 30.0;

    final markers = data.waypoints.map((wpt) {
      final color = WaypointIcons.colorFor(wpt.type);
      final icon = WaypointIcons.iconFor(wpt.type);
      final isSelected = wpt.id == provider.selectedPointId;
      final idx = stackIndex[wpt.id] ?? 0;
      // Extra height so the translated content doesn't get clipped by the
      // Marker bounding box on platforms that do enforce clipping.
      final extraHeight = idx * stackStep;

      return Marker(
        point: wpt.latLng,
        width: 36,
        height: 44 + extraHeight,
        alignment: Alignment.topCenter,
        child: Transform.translate(
          offset: Offset(0, -idx * stackStep),
          child: GestureDetector(
            onTap: () {
              if (provider.editMode == EditMode.deletePoint) {
                provider.removeWaypoint(wpt.id);
              } else {
                provider.selectPoint(wpt.id);
              }
            },
            onPanStart: (_) {
              _draggingPointId = wpt.id;
              _isDraggingWaypoint = true;
            },
            onPanUpdate: (details) {
              if (_draggingPointId != null && _isDraggingWaypoint) {
                final renderBox = context.findRenderObject() as RenderBox;
                final localPos = renderBox.globalToLocal(details.globalPosition);
                final point = _mapController.camera.pointToLatLng(
                  math.Point(localPos.dx, localPos.dy),
                );
                provider.moveWaypoint(_draggingPointId!, point);
              }
            },
            onPanEnd: (_) {
              _draggingPointId = null;
              _isDraggingWaypoint = false;
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? Colors.white : Colors.transparent,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.4),
                        blurRadius: isSelected ? 8 : 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 18),
                ),
                // Only the bottom (primary) marker draws the triangle
                // pointer so the stack reads as one pin with extra
                // icons floating above it, not a ladder of pins.
                if (idx == 0)
                  CustomPaint(
                    size: const Size(10, 8),
                    painter: _TrianglePainter(color),
                  ),
              ],
            ),
          ),
        ),
      );
    }).toList();

    return MarkerLayer(markers: markers);
  }

  /// Returns the poly-line vertices that lie between [start] and [end]
  /// cumulative distances along the profile, with interpolated endpoints
  /// so the highlight snaps exactly onto the climb bounds rather than to
  /// the nearest recorded track point.
  static List<LatLng> _climbLatLngs(
    ElevationProfile profile,
    double start,
    double end,
  ) {
    final result = <LatLng>[profile.sampleAtDistance(start).latLng];
    for (var i = 0; i < profile.length; i++) {
      final d = profile.distances[i];
      if (d > start && d < end) result.add(profile.points[i].latLng);
    }
    result.add(profile.sampleAtDistance(end).latLng);
    return result;
  }

  /// Coordinate key for grouping stacked waypoints. Rounded to ~1 m so
  /// two imports from the same source that differ only by floating-point
  /// precision still end up in the same stack.
  static String _coordKey(LatLng p) {
    return '${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}';
  }

  MouseCursor _cursorForMode(EditMode mode) {
    switch (mode) {
      case EditMode.view:
        return SystemMouseCursors.grab;
      case EditMode.addPoint:
      case EditMode.addWaypoint:
        return SystemMouseCursors.precise;
      case EditMode.deletePoint:
        return SystemMouseCursors.precise;
    }
  }

  IconData _iconForMode(EditMode mode) {
    switch (mode) {
      case EditMode.view:
        return Icons.pan_tool_rounded;
      case EditMode.addPoint:
        return Icons.add_location_alt_rounded;
      case EditMode.addWaypoint:
        return Icons.add_location_rounded;
      case EditMode.deletePoint:
        return Icons.delete_rounded;
    }
  }

  String _labelForMode(EditMode mode) {
    switch (mode) {
      case EditMode.view:
        return 'View mode';
      case EditMode.addPoint:
        return 'Click map to add track point';
      case EditMode.addWaypoint:
        return 'Click map to add waypoint';
      case EditMode.deletePoint:
        return 'Click a point to delete it';
    }
  }
}

class _TrianglePainter extends CustomPainter {
  _TrianglePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = ui.Path()
      ..moveTo(size.width / 2, size.height)
      ..lineTo(0, 0)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LayerMenuButton extends StatelessWidget {
  const _LayerMenuButton({
    required this.current,
    required this.mapyEnabled,
    required this.onChanged,
  });

  final _MapLayer current;
  final bool mapyEnabled;
  final ValueChanged<_MapLayer> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      elevation: 2,
      child: SizedBox(
        width: 36,
        height: 36,
        child: PopupMenuButton<_MapLayer>(
          tooltip: 'Map style',
          padding: EdgeInsets.zero,
          position: PopupMenuPosition.under,
          offset: const Offset(-160, 0),
          icon: Icon(
            Icons.layers_rounded,
            size: 20,
            color: AppTheme.textPrimary,
          ),
          onSelected: onChanged,
          itemBuilder: (ctx) => [
            CheckedPopupMenuItem<_MapLayer>(
              value: _MapLayer.standard,
              checked: current == _MapLayer.standard,
              child: const Text('Topographic (OpenTopoMap)'),
            ),
            CheckedPopupMenuItem<_MapLayer>(
              value: _MapLayer.outdoor,
              checked: current == _MapLayer.outdoor,
              enabled: mapyEnabled,
              child: Text(
                mapyEnabled
                    ? 'Outdoor (Mapy.com)'
                    : 'Outdoor (Mapy.com) — API key missing',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EndpointBadge extends StatelessWidget {
  const _EndpointBadge({
    required this.color,
    required this.icon,
    required this.tooltip,
  });

  final Color color;
  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.white, size: 14),
      ),
    );
  }
}

class _HoverTooltip extends StatelessWidget {
  const _HoverTooltip({
    required this.cursor,
    required this.distance,
    required this.elevation,
  });

  final Offset cursor;
  final double distance;
  final double? elevation;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) {
            const width = 140.0;
            const height = 44.0;
            double left = cursor.dx + 14;
            double top = cursor.dy + 14;
            if (left + width > constraints.maxWidth - 4) {
              left = cursor.dx - width - 14;
            }
            if (top + height > constraints.maxHeight - 4) {
              top = cursor.dy - height - 14;
            }
            if (left < 4) left = 4;
            if (top < 4) top = 4;

            return Stack(
              children: [
                Positioned(
                  left: left,
                  top: top,
                  child: Container(
              width: width,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.straighten_rounded,
                        size: 12,
                        color: AppTheme.primaryColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        GeoUtils.formatDistance(distance),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        Icons.terrain_rounded,
                        size: 12,
                        color: AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        elevation != null
                            ? '${elevation!.round()} m'
                            : 'No elevation',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        elevation: 2,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 20, color: AppTheme.textPrimary),
          ),
        ),
      ),
    );
  }
}
