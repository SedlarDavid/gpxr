import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/gpx_models.dart';
import '../providers/gpx_provider.dart';
import '../utils/climb_detector.dart';
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
    _tabController = TabController(length: 3, vsync: this);
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
            labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            tabs: const [
              Tab(text: 'Points'),
              Tab(text: 'Waypoints'),
              Tab(text: 'Climbs'),
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                _TrackPointsList(),
                _WaypointsList(),
                _ClimbsList(),
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
        final profile = ElevationProfile.fromPoints(trackPoints);
        final ticks = <WaypointTick>[];
        if (!profile.isEmpty) {
          for (final wpt in data.waypoints) {
            final nearest = profile.nearestOnTrack(wpt.latLng);
            if (nearest == null) continue;
            ticks.add(WaypointTick(
              distance: nearest.distance,
              color: WaypointIcons.colorFor(wpt.type),
              offTrack: nearest.distanceToLineMeters > GpxProvider.snapTolerance,
            ));
          }
        }

        // Prefer the GPX `<name>` element when set; otherwise fall back
        // to the source filename without extension, which is what the
        // user knows the file as. Only show "Untitled Route" as a last
        // resort (e.g. a brand-new empty route).
        final displayName = _firstNonBlank(data.name) ??
            _filenameAsTitle(provider.fileName) ??
            'Untitled Route';

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      displayName,
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
                profile: profile,
                hoverDistance: provider.hoverDistance,
                waypointTicks: ticks,
              ),
            ],
          ),
        );
      },
    );
  }

  static String? _firstNonBlank(String? s) {
    if (s == null) return null;
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  /// Turns a filename like `tor-des-geants-2024.gpx` into a friendly
  /// display title by stripping the extension. Returns null if the
  /// filename is missing or blank so the caller can fall back further.
  static String? _filenameAsTitle(String? fileName) {
    final name = _firstNonBlank(fileName);
    if (name == null) return null;
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    return _firstNonBlank(stem);
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

        final profile = provider.elevationProfile();
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
            final nearest = profile.isEmpty ? null : profile.nearestOnTrack(wpt.latLng);
            final onTrack = nearest != null &&
                nearest.distanceToLineMeters <= GpxProvider.snapTolerance;
            return _WaypointTile(
              key: ValueKey(wpt.id),
              waypoint: wpt,
              isSelected: isSelected,
              cumulativeDistance: nearest?.distance,
              offTrackMeters: (nearest != null && !onTrack)
                  ? nearest.distanceToLineMeters
                  : null,
              onTap: () => provider.selectPoint(wpt.id),
              onDelete: () => provider.removeWaypoint(wpt.id),
              onEdit: () => _editWaypoint(context, provider, wpt),
              onSnap: (nearest != null && !onTrack)
                  ? () => provider.snapWaypointToTrack(wpt.id)
                  : null,
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
    this.cumulativeDistance,
    this.offTrackMeters,
    this.onSnap,
  });

  final GpxWaypoint waypoint;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  /// Cumulative distance along the track (meters) where this waypoint
  /// projects. Null when there is no track to project onto.
  final double? cumulativeDistance;

  /// If the waypoint is farther from the track than the snap tolerance,
  /// the perpendicular distance (meters). Null when it's on-track.
  final double? offTrackMeters;

  /// Called when the user taps the "snap to track" action. Only provided
  /// when the waypoint is currently off-track.
  final VoidCallback? onSnap;

  @override
  Widget build(BuildContext context) {
    final color = WaypointIcons.colorFor(waypoint.type);
    final icon = WaypointIcons.iconFor(waypoint.type);

    final detailWidgets = <Widget>[
      Text(
        waypoint.type.label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    ];
    if (cumulativeDistance != null) {
      detailWidgets
        ..add(Text(' · ', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)))
        ..add(Text(
          '@ ${GeoUtils.formatDistance(cumulativeDistance!)}',
          style: TextStyle(
            fontSize: 11,
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ));
    }
    if (offTrackMeters != null) {
      detailWidgets
        ..add(const SizedBox(width: 4))
        ..add(Icon(Icons.warning_amber_rounded, size: 12, color: const Color(0xFFF59E0B)))
        ..add(const SizedBox(width: 2))
        ..add(Text(
          '${offTrackMeters!.round()}m off',
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFFB45309),
            fontWeight: FontWeight.w500,
          ),
        ));
    }

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
                  Row(children: detailWidgets),
                ],
              ),
            ),
            if (onSnap != null)
              IconButton(
                icon: const Icon(Icons.near_me_rounded, size: 14),
                onPressed: onSnap,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: 'Snap to track',
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

class _ClimbsList extends StatelessWidget {
  const _ClimbsList();

  @override
  Widget build(BuildContext context) {
    return Consumer<GpxProvider>(
      builder: (context, provider, _) {
        final profile = provider.elevationProfile();
        if (profile.isEmpty || !profile.hasElevation) {
          return _ClimbsEmpty(
            icon: Icons.landscape_rounded,
            title: 'No elevation data',
            subtitle: 'Import a GPX with elevation to see climb analysis.',
          );
        }
        final climbs = ClimbDetector.detect(profile);
        if (climbs.isEmpty) {
          return _ClimbsEmpty(
            icon: Icons.landscape_rounded,
            title: 'No significant climbs',
            subtitle:
                'This track is relatively flat — climbs under 30 m gain or 300 m length are ignored.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: climbs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 2),
          itemBuilder: (context, index) {
            return _ClimbTile(
              climb: climbs[index],
              index: index,
            );
          },
        );
      },
    );
  }
}

class _ClimbsEmpty extends StatelessWidget {
  const _ClimbsEmpty({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32,
                color: AppTheme.textSecondary.withValues(alpha: 0.4)),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
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
}

class _ClimbTile extends StatelessWidget {
  const _ClimbTile({required this.climb, required this.index});

  final Climb climb;
  final int index;

  @override
  Widget build(BuildContext context) {
    final avgPct = climb.averageGrade * 100;
    final maxPct = climb.maxGrade * 100;
    final gradeColor = _gradeColor(avgPct);
    final categoryColor = _categoryColor(climb.category);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppTheme.borderColor.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: gradeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: gradeColor,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Climb ${index + 1}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${GeoUtils.formatDistance(climb.startDistance)} → '
                      '${GeoUtils.formatDistance(climb.endDistance)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: categoryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  climb.category.label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: categoryColor,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _ClimbStat(
                icon: Icons.straighten_rounded,
                label: GeoUtils.formatDistance(climb.length),
                tooltip: 'Length',
              ),
              const SizedBox(width: 6),
              _ClimbStat(
                icon: Icons.trending_up_rounded,
                label: '+${climb.gain.round()} m',
                tooltip: 'Elevation gain',
                color: const Color(0xFF22C55E),
              ),
              const SizedBox(width: 6),
              _ClimbStat(
                icon: Icons.show_chart_rounded,
                label: '${avgPct.toStringAsFixed(1)}%',
                tooltip: 'Average grade',
                color: gradeColor,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.bolt_rounded, size: 12, color: AppTheme.textSecondary),
              const SizedBox(width: 3),
              Text(
                'Max ${maxPct.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _gradeColor(maxPct),
                ),
              ),
              const SizedBox(width: 10),
              Icon(Icons.height_rounded, size: 12, color: AppTheme.textSecondary),
              const SizedBox(width: 3),
              Text(
                '${climb.startElevation.round()} → ${climb.endElevation.round()} m',
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Grade color matching what most cycling/running apps use: green up
  /// to ~4%, yellow to 7%, orange to 10%, red to 15%, dark red beyond.
  static Color _gradeColor(double pct) {
    if (pct < 4) return const Color(0xFF22C55E);
    if (pct < 7) return const Color(0xFFEAB308);
    if (pct < 10) return const Color(0xFFF97316);
    if (pct < 15) return const Color(0xFFEF4444);
    return const Color(0xFF991B1B);
  }

  static Color _categoryColor(ClimbCategory c) {
    switch (c) {
      case ClimbCategory.cat4:
        return const Color(0xFF64748B);
      case ClimbCategory.cat3:
        return const Color(0xFF0EA5E9);
      case ClimbCategory.cat2:
        return const Color(0xFF8B5CF6);
      case ClimbCategory.cat1:
        return const Color(0xFFF97316);
      case ClimbCategory.hc:
        return const Color(0xFFEF4444);
    }
  }
}

class _ClimbStat extends StatelessWidget {
  const _ClimbStat({
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
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: AppTheme.borderColor.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color ?? AppTheme.textSecondary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
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
