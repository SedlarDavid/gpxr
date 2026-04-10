import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/gpx_models.dart';
import '../providers/gpx_provider.dart';
import '../utils/elevation_profile.dart';
import '../utils/geo_utils.dart';
import '../utils/theme.dart';
import '../utils/waypoint_icons.dart';
import 'elevation_profile_chart.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<GpxProvider>(
      builder: (context, provider, _) {
        if (!provider.hasData) {
          return const _EmptyState();
        }
        return const _SidebarContent();
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 340,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          right: BorderSide(color: AppTheme.borderColor),
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.route_rounded,
                size: 48,
                color: AppTheme.textSecondary.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 16),
              Text(
                'No route loaded',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Import a GPX file or create a new route to get started',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.textSecondary.withValues(alpha: 0.7),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarContent extends StatefulWidget {
  const _SidebarContent();

  @override
  State<_SidebarContent> createState() => _SidebarContentState();
}

class _SidebarContentState extends State<_SidebarContent>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 340,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          right: BorderSide(color: AppTheme.borderColor),
        ),
      ),
      child: Column(
        children: [
          const _RouteStats(),
          const Divider(height: 1),
          TabBar(
            controller: _tabController,
            labelColor: AppTheme.primaryColor,
            unselectedLabelColor: AppTheme.textSecondary,
            indicatorColor: AppTheme.primaryColor,
            indicatorSize: TabBarIndicatorSize.tab,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            tabs: const [
              Tab(text: 'Track Points'),
              Tab(text: 'Waypoints'),
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                _TrackPointsList(),
                _WaypointsList(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteStats extends StatelessWidget {
  const _RouteStats();

  @override
  Widget build(BuildContext context) {
    return Consumer<GpxProvider>(
      builder: (context, provider, _) {
        final data = provider.data!;
        final trackPoints = data.tracks.expand((t) => t.allPoints).toList();
        final routeLatLngs = data.allLinePoints;
        final distance = GeoUtils.totalDistance(routeLatLngs);
        final gain = GeoUtils.totalElevationGain(trackPoints);
        final loss = GeoUtils.totalElevationLoss(trackPoints);

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      data.name ?? 'Untitled Route',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_rounded, size: 16),
                    onPressed: () => _editRouteName(context, provider),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Edit name',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _StatChip(
                    icon: Icons.straighten_rounded,
                    label: GeoUtils.formatDistance(distance),
                    tooltip: 'Total distance',
                  ),
                  const SizedBox(width: 8),
                  _StatChip(
                    icon: Icons.trending_up_rounded,
                    label: GeoUtils.formatElevation(gain),
                    tooltip: 'Elevation gain',
                    color: const Color(0xFF22C55E),
                  ),
                  const SizedBox(width: 8),
                  _StatChip(
                    icon: Icons.trending_down_rounded,
                    label: GeoUtils.formatElevation(loss),
                    tooltip: 'Elevation loss',
                    color: const Color(0xFFEF4444),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _StatChip(
                    icon: Icons.location_on_rounded,
                    label: '${trackPoints.length} pts',
                    tooltip: 'Track points',
                  ),
                  const SizedBox(width: 8),
                  _StatChip(
                    icon: Icons.flag_rounded,
                    label: '${data.waypoints.length} wpts',
                    tooltip: 'Waypoints',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ElevationProfileChart(
                profile: ElevationProfile.fromPoints(trackPoints),
                hoverDistance: provider.hoverDistance,
              ),
            ],
          ),
        );
      },
    );
  }

  void _editRouteName(BuildContext context, GpxProvider provider) {
    final controller = TextEditingController(text: provider.data?.name ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Route Name', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Enter route name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              provider.updateRouteName(controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.tooltip,
    this.color,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color ?? AppTheme.textSecondary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackPointsList extends StatelessWidget {
  const _TrackPointsList();

  @override
  Widget build(BuildContext context) {
    return Consumer<GpxProvider>(
      builder: (context, provider, _) {
        final data = provider.data!;
        final points = data.tracks.isEmpty
            ? <GpxTrackPoint>[]
            : data.tracks.first.allPoints;

        if (points.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_location_alt_rounded, size: 32,
                      color: AppTheme.textSecondary.withValues(alpha: 0.4)),
                  const SizedBox(height: 8),
                  Text(
                    'No track points yet',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Use the add point tool to place points on the map',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.textSecondary.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return ReorderableListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: points.length,
          onReorder: provider.reorderTrackPoints,
          proxyDecorator: (child, index, animation) {
            return Material(
              color: Colors.transparent,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: child,
              ),
            );
          },
          itemBuilder: (context, index) {
            final pt = points[index];
            final isSelected = pt.id == provider.selectedPointId;
            final prevPoint = index > 0 ? points[index - 1] : null;
            final distFromPrev = prevPoint != null
                ? GeoUtils.distanceBetween(prevPoint.latLng, pt.latLng)
                : null;

            return _TrackPointTile(
              key: ValueKey(pt.id),
              point: pt,
              index: index,
              isSelected: isSelected,
              distFromPrev: distFromPrev,
              onTap: () => provider.selectPoint(pt.id),
              onDelete: () => provider.removeTrackPoint(pt.id),
            );
          },
        );
      },
    );
  }
}

class _TrackPointTile extends StatelessWidget {
  const _TrackPointTile({
    super.key,
    required this.point,
    required this.index,
    required this.isSelected,
    this.distFromPrev,
    required this.onTap,
    required this.onDelete,
  });

  final GpxTrackPoint point;
  final int index;
  final bool isSelected;
  final double? distFromPrev;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor.withValues(alpha: 0.05) : null,
          border: Border(
            left: BorderSide(
              color: isSelected ? AppTheme.primaryColor : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.drag_indicator_rounded, size: 16, color: Color(0xFFD1D5DB)),
            const SizedBox(width: 4),
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.primaryColor.withValues(alpha: 0.1)
                    : AppTheme.surfaceColor,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? AppTheme.primaryColor : AppTheme.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${point.latLng.latitude.toStringAsFixed(5)}, ${point.latLng.longitude.toStringAsFixed(5)}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  Row(
                    children: [
                      if (point.elevation != null)
                        Text(
                          'Ele: ${point.elevation!.round()}m',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      if (point.elevation != null && distFromPrev != null)
                        Text(' · ', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                      if (distFromPrev != null)
                        Text(
                          GeoUtils.formatDistance(distFromPrev!),
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 14),
              onPressed: onDelete,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: 'Remove point',
            ),
          ],
        ),
      ),
    );
  }
}

class _WaypointsList extends StatelessWidget {
  const _WaypointsList();

  @override
  Widget build(BuildContext context) {
    return Consumer<GpxProvider>(
      builder: (context, provider, _) {
        final waypoints = provider.data!.waypoints;

        if (waypoints.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.flag_rounded, size: 32,
                      color: AppTheme.textSecondary.withValues(alpha: 0.4)),
                  const SizedBox(height: 8),
                  Text(
                    'No waypoints yet',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Add stops like aid stations, summits, or water sources',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.textSecondary.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return ReorderableListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: waypoints.length,
          onReorder: provider.reorderWaypoints,
          proxyDecorator: (child, index, animation) {
            return Material(
              color: Colors.transparent,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: child,
              ),
            );
          },
          itemBuilder: (context, index) {
            final wpt = waypoints[index];
            final isSelected = wpt.id == provider.selectedPointId;
            return _WaypointTile(
              key: ValueKey(wpt.id),
              waypoint: wpt,
              isSelected: isSelected,
              onTap: () => provider.selectPoint(wpt.id),
              onDelete: () => provider.removeWaypoint(wpt.id),
              onEdit: () => _editWaypoint(context, provider, wpt),
            );
          },
        );
      },
    );
  }

  void _editWaypoint(BuildContext context, GpxProvider provider, GpxWaypoint wpt) {
    final nameController = TextEditingController(text: wpt.name);
    final descController = TextEditingController(text: wpt.description);
    WaypointType selectedType = wpt.type;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Edit Waypoint', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(labelText: 'Description'),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                Text('Type', style: Theme.of(ctx).textTheme.labelMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: WaypointType.values.map((type) {
                    final isActive = type == selectedType;
                    return FilterChip(
                      selected: isActive,
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            WaypointIcons.iconFor(type),
                            size: 16,
                            color: isActive
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
                provider.updateWaypoint(
                  wpt.id,
                  name: nameController.text,
                  description: descController.text.isEmpty ? null : descController.text,
                  type: selectedType,
                );
                Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _WaypointTile extends StatelessWidget {
  const _WaypointTile({
    super.key,
    required this.waypoint,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
    required this.onEdit,
  });

  final GpxWaypoint waypoint;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final color = WaypointIcons.colorFor(waypoint.type);
    final icon = WaypointIcons.iconFor(waypoint.type);

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.05) : null,
          border: Border(
            left: BorderSide(
              color: isSelected ? color : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.drag_indicator_rounded, size: 16, color: Color(0xFFD1D5DB)),
            const SizedBox(width: 4),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    waypoint.name ?? 'Unnamed',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    waypoint.type.label,
                    style: TextStyle(
                      fontSize: 11,
                      color: color,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_rounded, size: 14),
              onPressed: onEdit,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: 'Edit waypoint',
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 14),
              onPressed: onDelete,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: 'Remove waypoint',
            ),
          ],
        ),
      ),
    );
  }
}
