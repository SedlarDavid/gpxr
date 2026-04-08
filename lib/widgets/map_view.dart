import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/gpx_models.dart';
import '../providers/gpx_provider.dart';
import '../utils/geo_utils.dart';
import '../utils/theme.dart';
import '../utils/waypoint_icons.dart';

class MapView extends StatefulWidget {
  const MapView({super.key});

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  final MapController _mapController = MapController();
  String? _draggingPointId;
  bool _isDraggingWaypoint = false;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _fitBounds(GpxData data) {
    final allPoints = <LatLng>[
      ...data.allLinePoints,
      ...data.waypoints.map((w) => w.latLng),
    ];
    if (allPoints.isEmpty) return;

    if (allPoints.length == 1) {
      _mapController.move(allPoints.first, 14);
      return;
    }

    final center = GeoUtils.center(allPoints);
    final zoom = GeoUtils.fitZoom(allPoints);
    _mapController.move(center, zoom);
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

        return MouseRegion(
          cursor: cursorStyle,
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
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.gpxr.app',
                    maxZoom: 19,
                  ),
                  if (data != null) ..._buildTrackLayers(data, provider),
                  if (data != null && provider.showWaypoints)
                    _buildWaypointLayer(data, provider),
                ],
              ),
              // Fit bounds button
              if (data != null && allPoints.isNotEmpty)
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: _MapButton(
                    icon: Icons.fit_screen_rounded,
                    tooltip: 'Fit to route',
                    onTap: () => _fitBounds(data),
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
    final markers = data.waypoints.map((wpt) {
      final color = WaypointIcons.colorFor(wpt.type);
      final icon = WaypointIcons.iconFor(wpt.type);
      final isSelected = wpt.id == provider.selectedPointId;

      return Marker(
        point: wpt.latLng,
        width: 36,
        height: 44,
        alignment: Alignment.topCenter,
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
              CustomPaint(
                size: const Size(10, 8),
                painter: _TrianglePainter(color),
              ),
            ],
          ),
        ),
      );
    }).toList();

    return MarkerLayer(markers: markers);
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
