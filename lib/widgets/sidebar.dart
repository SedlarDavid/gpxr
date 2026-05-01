import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/gpx_models.dart';
import '../providers/gpx_provider.dart';
import '../utils/climb_detector.dart';
import '../utils/descent_detector.dart';
import '../utils/geo_utils.dart';
import '../utils/theme.dart';
import '../utils/waypoint_icons.dart';
import 'add_waypoint_by_distance_dialog.dart';
import 'elevation_profile_chart.dart';
import 'profile_detail_view.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({super.key, this.mobile = false, this.width});

  /// When true the sidebar fills the parent's width (used in the mobile
  /// bottom-sheet layout) instead of being a fixed 340px-wide column
  /// with a right divider.
  final bool mobile;

  /// Desktop-only override for the sidebar's width. Ignored when
  /// [mobile] is true. Defaults to 340 when unset.
  final double? width;

  @override
  Widget build(BuildContext context) {
    AppTheme.subscribe(context);
    return Consumer<GpxProvider>(
      builder: (context, provider, _) {
        if (!provider.hasData) {
          return _EmptyState(mobile: mobile, width: width);
        }
        return _SidebarContent(mobile: mobile, width: width);
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.mobile = false, this.width});

  final bool mobile;
  final double? width;

  @override
  Widget build(BuildContext context) {
    AppTheme.subscribe(context);
    return Container(
      width: mobile ? null : (width ?? 340),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        border: mobile
            ? null
            : Border(right: BorderSide(color: AppTheme.borderColor)),
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
  const _SidebarContent({this.mobile = false, this.width});

  final bool mobile;
  final double? width;

  @override
  State<_SidebarContent> createState() => _SidebarContentState();
}

class _SidebarContentState extends State<_SidebarContent>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.subscribe(context);
    return Container(
      width: widget.mobile ? null : (widget.width ?? 340),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        border: widget.mobile
            ? null
            : Border(right: BorderSide(color: AppTheme.borderColor)),
      ),
      child: Column(
        children: [
          // _RouteStats sits inline (no Flexible/SCV wrapper) so it
          // takes only its intrinsic height and the Expanded TabBarView
          // below gets every remaining pixel. Wrapping it in
          // Flexible(loose) used to leave white space at the bottom of
          // the list because Flexible competes with Expanded for half
          // the column's free space and the loose half went unused.
          const _RouteStats(),
          const Divider(height: 1),
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppTheme.primaryColor,
            unselectedLabelColor: AppTheme.textSecondary,
            indicatorColor: AppTheme.primaryColor,
            indicatorSize: TabBarIndicatorSize.tab,
            labelStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            tabs: const [
              Tab(text: 'Tracks'),
              Tab(text: 'Points'),
              Tab(text: 'Waypoints'),
              Tab(text: 'Climbs'),
              Tab(text: 'Descents'),
              Tab(text: 'Splits'),
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                TracksList(),
                _TrackPointsList(),
                WaypointsList(),
                ClimbsList(),
                DescentsList(),
                SplitsList(),
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
    AppTheme.subscribe(context);
    return Consumer<GpxProvider>(
      builder: (context, provider, _) {
        final data = provider.data!;
        // Sum per-track stats rather than computing on a flattened
        // point list. Concatenating tracks across the Bergen↔Voss↔Oslo
        // boundaries used to add ~500 km of phantom haversine distance
        // and a phantom 1000+ m climb where one track's last point
        // jumped to the next track's first point.
        final visible = provider.visibleTracks;
        double distance = 0;
        double gain = 0;
        double loss = 0;
        int trackPointCount = 0;
        for (final track in visible) {
          final pts = track.allPoints;
          trackPointCount += pts.length;
          distance += GeoUtils.totalDistance(
            pts.map((p) => p.latLng).toList(growable: false),
          );
          gain += GeoUtils.totalElevationGain(pts);
          loss += GeoUtils.totalElevationLoss(pts);
        }
        // Routes (rte) still get their distance added since they're a
        // single polyline, but they're rare in this UI's main flow.
        distance += GeoUtils.totalDistance(data.allRoutePoints);
        final profile = provider.elevationProfile();
        final ticks = <WaypointTick>[];
        if (!profile.isEmpty) {
          for (final wpt in data.waypoints) {
            // Cached per-waypoint projection — was the dominant cost
            // here at 45k profile points × N waypoints (each call is
            // an O(N) haversine scan over the polyline).
            final nearest = provider.nearestOnTrackForWaypoint(wpt);
            if (nearest == null) continue;
            ticks.add(
              WaypointTick(
                distance: nearest.distance,
                color: WaypointIcons.colorFor(wpt.type),
                icon: WaypointIcons.iconFor(wpt.type),
                offTrack:
                    nearest.distanceToLineMeters > GpxProvider.snapTolerance,
              ),
            );
          }
        }

        // Prefer the GPX `<name>` element when set; otherwise fall back
        // to the source filename without extension, which is what the
        // user knows the file as. Only show "Untitled Route" as a last
        // resort (e.g. a brand-new empty route).
        final displayName =
            _firstNonBlank(data.name) ??
            _filenameAsTitle(provider.fileName) ??
            'Untitled Route';

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            // Take only the natural intrinsic height of the children,
            // never the parent's full height. Without this, when this
            // widget is placed unwrapped in another Column, the inner
            // Column would default to mainAxisSize.max and try to grow
            // forever / steal space from the list below.
            mainAxisSize: MainAxisSize.min,
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
                    label: '$trackPointCount pts',
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
              Stack(
                children: [
                  ElevationProfileChart(
                    profile: profile,
                    hoverDistance: provider.hoverDistance,
                    waypointTicks: ticks,
                  ),
                  // Launcher for the full-screen profile detail view —
                  // small enough to not steal cursor area on the chart,
                  // but visible so the feature is discoverable.
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Material(
                      color: AppTheme.cardColor.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(6),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => showProfileDetailDialog(context),
                        child: Tooltip(
                          message: 'Open profile detail',
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.open_in_full_rounded,
                              size: 14,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
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
        title: const Text(
          'Route Name',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
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
    AppTheme.subscribe(context);
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

/// Per-track summary tab. Lists every track in the loaded data with its
/// distance, elevation gain/loss and point count, plus controls to
/// toggle visibility, recolor, rename or remove the track. The point
/// of this view is to make a multi-file merge legible: each imported
/// GPX shows up as its own row with its own color, and the global
/// stats panel above the tab bar already aggregates the visible ones.
class TracksList extends StatelessWidget {
  const TracksList({super.key});

  @override
  Widget build(BuildContext context) {
    AppTheme.subscribe(context);
    return Consumer<GpxProvider>(
      builder: (context, provider, _) {
        final tracks = provider.data?.tracks ?? const <GpxTrack>[];
        if (tracks.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.route_rounded,
                    size: 32,
                    color: AppTheme.textSecondary.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No tracks loaded',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Use Import GPX or Merge GPX from the menu to add tracks.',
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

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 64),
          itemCount: tracks.length,
          separatorBuilder: (_, _) => const SizedBox(height: 2),
          itemBuilder: (context, index) {
            final track = tracks[index];
            final points = track.allPoints;
            final latLngs = points.map((p) => p.latLng).toList();
            final distance = GeoUtils.totalDistance(latLngs);
            final gain = GeoUtils.totalElevationGain(points);
            final loss = GeoUtils.totalElevationLoss(points);
            return _TrackTile(
              track: track,
              index: index,
              distance: distance,
              gain: gain,
              loss: loss,
              pointCount: points.length,
              color: provider.colorForTrack(track.id),
              visible: provider.isTrackVisible(track.id),
              canDelete: tracks.length > 1,
            );
          },
        );
      },
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.track,
    required this.index,
    required this.distance,
    required this.gain,
    required this.loss,
    required this.pointCount,
    required this.color,
    required this.visible,
    required this.canDelete,
  });

  final GpxTrack track;
  final int index;
  final double distance;
  final double gain;
  final double loss;
  final int pointCount;
  final Color color;
  final bool visible;

  /// Last surviving track has no delete button — removing the only
  /// track would leave the data with nothing to render and there's no
  /// "create empty track" pathway out of that state from this tab.
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    AppTheme.subscribe(context);
    final provider = context.read<GpxProvider>();
    final displayName = (track.name == null || track.name!.trim().isEmpty)
        ? 'Track ${index + 1}'
        : track.name!.trim();
    final dim = visible ? 1.0 : 0.45;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.borderColor.withValues(alpha: 0.5)),
      ),
      child: Opacity(
        opacity: dim,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _ColorSwatchButton(
                  color: color,
                  onTap: () => _pickColor(context, provider),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    displayName,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    visible
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                    size: 16,
                  ),
                  onPressed: () => provider.toggleTrackVisibility(track.id),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  tooltip: visible ? 'Hide track' : 'Show track',
                ),
                IconButton(
                  icon: const Icon(Icons.edit_rounded, size: 14),
                  onPressed: () => _renameTrack(context, provider, displayName),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  tooltip: 'Rename track',
                ),
                if (canDelete)
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 14),
                    onPressed: () =>
                        _confirmRemove(context, provider, displayName),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    tooltip: 'Remove track',
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _ClimbStat(
                  icon: Icons.straighten_rounded,
                  label: GeoUtils.formatDistance(distance),
                  tooltip: 'Distance',
                ),
                const SizedBox(width: 6),
                _ClimbStat(
                  icon: Icons.trending_up_rounded,
                  label: '+${gain.round()} m',
                  tooltip: 'Elevation gain',
                  color: const Color(0xFF22C55E),
                ),
                const SizedBox(width: 6),
                _ClimbStat(
                  icon: Icons.trending_down_rounded,
                  label: '\u2212${loss.round()} m',
                  tooltip: 'Elevation loss',
                  color: const Color(0xFFEF4444),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.circle, size: 7, color: AppTheme.textSecondary),
                const SizedBox(width: 4),
                Text(
                  '$pointCount pts',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (track.segments.length > 1) ...[
                  const SizedBox(width: 10),
                  Icon(
                    Icons.timeline_rounded,
                    size: 11,
                    color: AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${track.segments.length} segments',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _pickColor(BuildContext context, GpxProvider provider) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Track color',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        content: SizedBox(
          width: 280,
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: kRouteColorPresets.map((c) {
              final selected = c == color;
              return InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  provider.setTrackColor(track.id, c);
                  Navigator.pop(ctx);
                },
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected ? Colors.black : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _renameTrack(
    BuildContext context,
    GpxProvider provider,
    String currentName,
  ) {
    final controller = TextEditingController(text: currentName);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Rename track',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Track name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              provider.setTrackName(track.id, controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmRemove(
    BuildContext context,
    GpxProvider provider,
    String displayName,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Remove track?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Remove "$displayName" from this view? This does '
          'not affect the original GPX file on disk.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            onPressed: () {
              provider.removeTrack(track.id);
              Navigator.pop(ctx);
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}

class _ColorSwatchButton extends StatelessWidget {
  const _ColorSwatchButton({required this.color, required this.onTap});

  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    AppTheme.subscribe(context);
    return Tooltip(
      message: 'Change color',
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.black.withValues(alpha: 0.15)),
          ),
        ),
      ),
    );
  }
}

class _TrackPointsList extends StatelessWidget {
  const _TrackPointsList();

  @override
  Widget build(BuildContext context) {
    AppTheme.subscribe(context);
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
                  Icon(
                    Icons.add_location_alt_rounded,
                    size: 32,
                    color: AppTheme.textSecondary.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No track points yet',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                    ),
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
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 64),
          itemCount: points.length,
          onReorder: provider.reorderTrackPoints,
          proxyDecorator: (child, index, animation) {
            return Material(
              color: Colors.transparent,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppTheme.cardColor,
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
    AppTheme.subscribe(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryColor.withValues(alpha: 0.05)
              : null,
          border: Border(
            left: BorderSide(
              color: isSelected ? AppTheme.primaryColor : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.drag_indicator_rounded,
              size: 16,
              color: Color(0xFFD1D5DB),
            ),
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
                  color: isSelected
                      ? AppTheme.primaryColor
                      : AppTheme.textSecondary,
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
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
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
                        Text(
                          ' · ',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 11,
                          ),
                        ),
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

class WaypointsList extends StatelessWidget {
  const WaypointsList({super.key});

  @override
  Widget build(BuildContext context) {
    AppTheme.subscribe(context);
    return Consumer<GpxProvider>(
      builder: (context, provider, _) {
        final waypoints = provider.data!.waypoints;

        if (waypoints.isEmpty) {
          final hasTrack = !provider.elevationProfile().isEmpty;
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.flag_rounded,
                    size: 32,
                    color: AppTheme.textSecondary.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No waypoints yet',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                    ),
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
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: hasTrack
                        ? () =>
                              showAddWaypointByDistanceDialog(context, provider)
                        : null,
                    icon: const Icon(Icons.straighten_rounded, size: 16),
                    label: const Text('Add by km'),
                  ),
                ],
              ),
            ),
          );
        }

        final profile = provider.elevationProfile();
        return ReorderableListView.builder(
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 64),
          itemCount: waypoints.length,
          onReorder: provider.reorderWaypoints,
          proxyDecorator: (child, index, animation) {
            return Material(
              color: Colors.transparent,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppTheme.cardColor,
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
            final nearest = profile.isEmpty
                ? null
                : provider.nearestOnTrackForWaypoint(wpt);
            final onTrack =
                nearest != null &&
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

  void _editWaypoint(
    BuildContext context,
    GpxProvider provider,
    GpxWaypoint wpt,
  ) {
    final nameController = TextEditingController(text: wpt.name);
    final descController = TextEditingController(text: wpt.description);
    final cutoffController = TextEditingController(text: wpt.cutoff);
    WaypointType selectedType = wpt.type;

    final profile = provider.elevationProfile();
    final hasTrack = !profile.isEmpty;
    final totalKm = hasTrack ? profile.totalDistance / 1000 : 0.0;
    final trackInfo = hasTrack ? provider.waypointTrackInfo(wpt) : null;
    final currentKm = trackInfo != null ? trackInfo.distance / 1000 : null;
    final kmController = TextEditingController(
      text: currentKm != null ? currentKm.toStringAsFixed(2) : '',
    );

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Edit Waypoint',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
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
                const SizedBox(height: 12),
                TextField(
                  controller: cutoffController,
                  decoration: const InputDecoration(
                    labelText: 'Cutoff (optional)',
                    hintText: '12:30 or 4:15:00',
                    helperText: 'Race cutoff time at this waypoint',
                  ),
                ),
                if (hasTrack) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: kmController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Distance (km)',
                      hintText: 'e.g. 12.5',
                      helperText:
                          'Track length: ${totalKm.toStringAsFixed(2)} km — change to slide along route',
                    ),
                  ),
                ],
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
                final cutoffText = cutoffController.text.trim();
                provider.updateWaypoint(
                  wpt.id,
                  name: nameController.text,
                  description: descController.text.isEmpty
                      ? null
                      : descController.text,
                  type: selectedType,
                  cutoff: cutoffText.isEmpty ? null : cutoffText,
                  clearCutoff: cutoffText.isEmpty,
                );
                if (hasTrack) {
                  final newKm = double.tryParse(
                    kmController.text.replaceAll(',', '.'),
                  );
                  if (newKm != null &&
                      (currentKm == null ||
                          (newKm - currentKm).abs() > 0.001)) {
                    provider.moveWaypointToDistance(wpt.id, newKm * 1000);
                  }
                }
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
    AppTheme.subscribe(context);
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
        ..add(
          Text(
            ' · ',
            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
        )
        ..add(
          Text(
            '@ ${GeoUtils.formatDistance(cumulativeDistance!)}',
            style: TextStyle(
              fontSize: 11,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
    }
    if (offTrackMeters != null) {
      detailWidgets
        ..add(const SizedBox(width: 4))
        ..add(
          Icon(
            Icons.warning_amber_rounded,
            size: 12,
            color: const Color(0xFFF59E0B),
          ),
        )
        ..add(const SizedBox(width: 2))
        ..add(
          Text(
            '${offTrackMeters!.round()}m off',
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFFB45309),
              fontWeight: FontWeight.w500,
            ),
          ),
        );
    }
    if (waypoint.cutoff != null && waypoint.cutoff!.isNotEmpty) {
      detailWidgets
        ..add(
          Text(
            ' · ',
            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
        )
        ..add(
          Icon(Icons.timer_outlined, size: 11, color: const Color(0xFFEF4444)),
        )
        ..add(const SizedBox(width: 2))
        ..add(
          Text(
            waypoint.cutoff!,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFFEF4444),
              fontWeight: FontWeight.w600,
            ),
          ),
        );
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
            const Icon(
              Icons.drag_indicator_rounded,
              size: 16,
              color: Color(0xFFD1D5DB),
            ),
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
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
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

class ClimbsList extends StatelessWidget {
  const ClimbsList({super.key});

  @override
  Widget build(BuildContext context) {
    AppTheme.subscribe(context);
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
        final climbs = provider.climbs();
        if (climbs.isEmpty) {
          return _ClimbsEmpty(
            icon: Icons.landscape_rounded,
            title: 'No significant climbs',
            subtitle:
                'This track is relatively flat — climbs under 30 m gain or 300 m length are ignored.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 64),
          itemCount: climbs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 2),
          itemBuilder: (context, index) {
            return _ClimbTile(
              climb: climbs[index],
              index: index,
              activity: provider.activityType,
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
    AppTheme.subscribe(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 32,
              color: AppTheme.textSecondary.withValues(alpha: 0.4),
            ),
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
  const _ClimbTile({
    required this.climb,
    required this.index,
    required this.activity,
  });

  final Climb climb;
  final int index;
  final ActivityType activity;

  @override
  Widget build(BuildContext context) {
    AppTheme.subscribe(context);
    final avgPct = climb.averageGrade * 100;
    final maxPct = climb.maxGrade * 100;
    final gradeColor = _gradeColor(avgPct, activity);
    final category = climb.categoryFor(activity);
    final categoryColor = _categoryColor(category);
    final provider = context.read<GpxProvider>();

    return MouseRegion(
      onEnter: (_) => provider.hoveredClimbRange.value = (
        climb.startDistance,
        climb.endDistance,
      ),
      onExit: (_) => provider.hoveredClimbRange.value = null,
      child: Container(
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: categoryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    category.label,
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
                Icon(
                  Icons.bolt_rounded,
                  size: 12,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(width: 3),
                Text(
                  'Max ${maxPct.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _gradeColor(maxPct, activity),
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  Icons.height_rounded,
                  size: 12,
                  color: AppTheme.textSecondary,
                ),
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
      ),
    );
  }

  /// Grade color ramp. Cycling thresholds are tighter (anything > 7% is
  /// orange) because road riders rarely sustain steeper grades, while
  /// trail runners regularly hike pitches over 15% — so we shift the
  /// ramp upward for trail running so a normal trail climb still reads
  /// "moderate" rather than "very steep".
  static Color _gradeColor(double pct, ActivityType activity) {
    switch (activity) {
      case ActivityType.bike:
        if (pct < 4) return const Color(0xFF22C55E);
        if (pct < 7) return const Color(0xFFEAB308);
        if (pct < 10) return const Color(0xFFF97316);
        if (pct < 15) return const Color(0xFFEF4444);
        return const Color(0xFF991B1B);
      case ActivityType.trailRun:
        if (pct < 6) return const Color(0xFF22C55E);
        if (pct < 10) return const Color(0xFFEAB308);
        if (pct < 15) return const Color(0xFFF97316);
        if (pct < 22) return const Color(0xFFEF4444);
        return const Color(0xFF991B1B);
    }
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
      case ClimbCategory.easy:
        return const Color(0xFF22C55E);
      case ClimbCategory.moderate:
        return const Color(0xFF0EA5E9);
      case ClimbCategory.hard:
        return const Color(0xFF8B5CF6);
      case ClimbCategory.veryHard:
        return const Color(0xFFF97316);
      case ClimbCategory.brutal:
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
    AppTheme.subscribe(context);
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: AppTheme.cardColor,
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

/// Mirror of [ClimbsList] for descents. Trail runners care about descents
/// independently of climbs because eccentric quad load and braking on
/// long downhills (rather than climbing aerobic load) is what actually
/// limits performance and recovery in long ultras — so a route's
/// descents deserve their own first-class view.
class DescentsList extends StatelessWidget {
  const DescentsList({super.key});

  @override
  Widget build(BuildContext context) {
    AppTheme.subscribe(context);
    return Consumer<GpxProvider>(
      builder: (context, provider, _) {
        final profile = provider.elevationProfile();
        if (profile.isEmpty || !profile.hasElevation) {
          return _ClimbsEmpty(
            icon: Icons.trending_down_rounded,
            title: 'No elevation data',
            subtitle: 'Import a GPX with elevation to see descent analysis.',
          );
        }
        final descents = provider.descents();
        if (descents.isEmpty) {
          return _ClimbsEmpty(
            icon: Icons.trending_down_rounded,
            title: 'No significant descents',
            subtitle:
                'This track is relatively flat — descents under 30 m loss or 300 m length are ignored.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 64),
          itemCount: descents.length,
          separatorBuilder: (_, _) => const SizedBox(height: 2),
          itemBuilder: (context, index) {
            return _DescentTile(
              descent: descents[index],
              index: index,
              activity: provider.activityType,
            );
          },
        );
      },
    );
  }
}

class _DescentTile extends StatelessWidget {
  const _DescentTile({
    required this.descent,
    required this.index,
    required this.activity,
  });

  final Descent descent;
  final int index;
  final ActivityType activity;

  @override
  Widget build(BuildContext context) {
    AppTheme.subscribe(context);
    final avgPct = descent.averageGrade * 100;
    final maxPct = descent.maxGrade * 100;
    // Reuse the climb grade ramp — steepness is steepness regardless of
    // direction, and using the same color palette keeps the visual
    // language consistent for users scanning between the two tabs.
    final gradeColor = _ClimbTile._gradeColor(avgPct, activity);
    final category = descent.categoryFor(activity);
    final categoryColor = _descentCategoryColor(category);
    final provider = context.read<GpxProvider>();

    return MouseRegion(
      onEnter: (_) => provider.hoveredDescentRange.value = (
        descent.startDistance,
        descent.endDistance,
      ),
      onExit: (_) => provider.hoveredDescentRange.value = null,
      child: Container(
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
                        'Descent ${index + 1}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '${GeoUtils.formatDistance(descent.startDistance)} → '
                        '${GeoUtils.formatDistance(descent.endDistance)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Tooltip(
                  message: activity == ActivityType.trailRun
                      ? 'Estimated knee impact'
                      : 'Descent severity',
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: categoryColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      category.label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: categoryColor,
                        letterSpacing: 0.3,
                      ),
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
                  label: GeoUtils.formatDistance(descent.length),
                  tooltip: 'Length',
                ),
                const SizedBox(width: 6),
                _ClimbStat(
                  icon: Icons.trending_down_rounded,
                  label: '\u2212${descent.loss.round()} m',
                  tooltip: 'Elevation loss',
                  color: const Color(0xFFF97316),
                ),
                const SizedBox(width: 6),
                _ClimbStat(
                  icon: Icons.show_chart_rounded,
                  label: '\u2212${avgPct.toStringAsFixed(1)}%',
                  tooltip: 'Average descent grade',
                  color: gradeColor,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.bolt_rounded,
                  size: 12,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(width: 3),
                Text(
                  'Max \u2212${maxPct.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _ClimbTile._gradeColor(maxPct, activity),
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  Icons.height_rounded,
                  size: 12,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(width: 3),
                Text(
                  '${descent.startElevation.round()} → ${descent.endElevation.round()} m',
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
      ),
    );
  }

  static Color _descentCategoryColor(DescentCategory c) {
    switch (c) {
      case DescentCategory.cat4:
        return const Color(0xFF64748B);
      case DescentCategory.cat3:
        return const Color(0xFF0EA5E9);
      case DescentCategory.cat2:
        return const Color(0xFF8B5CF6);
      case DescentCategory.cat1:
        return const Color(0xFFF97316);
      case DescentCategory.hc:
        return const Color(0xFFEF4444);
      case DescentCategory.easy:
        return const Color(0xFF22C55E);
      case DescentCategory.moderate:
        return const Color(0xFF0EA5E9);
      case DescentCategory.hard:
        return const Color(0xFF8B5CF6);
      case DescentCategory.veryHard:
        return const Color(0xFFF97316);
      case DescentCategory.brutal:
        return const Color(0xFFEF4444);
    }
  }
}

/// Projects each waypoint onto the track and lists them in track order
/// with cumulative distance from start and "to next" leg distance — the
/// classic race-brief "aid-station table" most trail runners check before
/// a race.
class SplitsList extends StatelessWidget {
  const SplitsList({super.key});

  @override
  Widget build(BuildContext context) {
    AppTheme.subscribe(context);
    return Consumer<GpxProvider>(
      builder: (context, provider, _) {
        final data = provider.data;
        if (data == null) {
          return const _ClimbsEmpty(
            icon: Icons.flag_rounded,
            title: 'No waypoints',
            subtitle: 'Load a GPX with waypoints to see a splits table.',
          );
        }
        if (data.waypoints.isEmpty) {
          return const _ClimbsEmpty(
            icon: Icons.flag_rounded,
            title: 'No waypoints',
            subtitle:
                'Add waypoints on the map or import them from Trace de Trail '
                '(Tools menu).',
          );
        }
        final profile = provider.elevationProfile();
        if (profile.isEmpty) {
          return const _ClimbsEmpty(
            icon: Icons.flag_rounded,
            title: 'No track',
            subtitle: 'Splits need a track to project waypoints onto.',
          );
        }

        final rows = <_SplitRow>[];
        for (final wpt in data.waypoints) {
          final nearest = provider.nearestOnTrackForWaypoint(wpt);
          if (nearest == null) continue;
          rows.add(
            _SplitRow(
              name: _firstNonBlank(wpt.name) ?? _defaultName(wpt.type),
              distance: nearest.distance,
              color: WaypointIcons.colorFor(wpt.type),
              icon: WaypointIcons.iconFor(wpt.type),
              offTrack:
                  nearest.distanceToLineMeters > GpxProvider.snapTolerance,
              cutoff: wpt.cutoff,
            ),
          );
        }
        rows.sort((a, b) => a.distance.compareTo(b.distance));

        return Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor,
                border: Border(bottom: BorderSide(color: AppTheme.borderColor)),
              ),
              child: Row(
                children: const [
                  Expanded(
                    flex: 5,
                    child: Text(
                      'WAYPOINT',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 58,
                    child: Text(
                      'KM',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  SizedBox(
                    width: 58,
                    child: Text(
                      'TO NEXT',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(0, 2, 0, 64),
                itemCount: rows.length,
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  color: AppTheme.borderColor.withValues(alpha: 0.5),
                ),
                itemBuilder: (context, index) {
                  final row = rows[index];
                  final toNext = index < rows.length - 1
                      ? rows[index + 1].distance - row.distance
                      : 0.0;
                  final provider = context.read<GpxProvider>();
                  return MouseRegion(
                    onEnter: (_) {
                      if (index < rows.length - 1) {
                        provider.hoveredClimbRange.value = (
                          row.distance,
                          rows[index + 1].distance,
                        );
                      }
                    },
                    onExit: (_) => provider.hoveredClimbRange.value = null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 5,
                            child: Row(
                              children: [
                                Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: row.offTrack
                                        ? Colors.white
                                        : row.color,
                                    borderRadius: BorderRadius.circular(5),
                                    border: row.offTrack
                                        ? Border.all(
                                            color: row.color,
                                            width: 1.2,
                                          )
                                        : null,
                                  ),
                                  alignment: Alignment.center,
                                  child: Icon(
                                    row.icon,
                                    size: 13,
                                    color: row.offTrack
                                        ? row.color
                                        : Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        row.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      if (row.cutoff != null &&
                                          row.cutoff!.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 1,
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.timer_outlined,
                                                size: 11,
                                                color: Color(0xFFEF4444),
                                              ),
                                              const SizedBox(width: 3),
                                              Text(
                                                'cutoff ${row.cutoff!}',
                                                style: const TextStyle(
                                                  fontSize: 10.5,
                                                  color: Color(0xFFEF4444),
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 58,
                            child: Text(
                              GeoUtils.formatDistance(row.distance),
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 58,
                            child: Text(
                              toNext > 0
                                  ? GeoUtils.formatDistance(toNext)
                                  : '—',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: toNext > 0
                                    ? AppTheme.textSecondary
                                    : AppTheme.textSecondary.withValues(
                                        alpha: 0.5,
                                      ),
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  static String? _firstNonBlank(String? s) =>
      (s != null && s.trim().isNotEmpty) ? s.trim() : null;

  static String _defaultName(WaypointType type) {
    switch (type) {
      case WaypointType.aidStation:
        return 'Aid station';
      case WaypointType.medical:
        return 'Medical';
      case WaypointType.water:
        return 'Water';
      case WaypointType.food:
        return 'Food';
      case WaypointType.summit:
        return 'Summit';
      case WaypointType.camp:
        return 'Camp';
      case WaypointType.parking:
        return 'Parking';
      case WaypointType.danger:
        return 'Danger';
      case WaypointType.info:
        return 'Info';
      case WaypointType.start:
        return 'Start';
      case WaypointType.finish:
        return 'Finish';
      case WaypointType.generic:
        return 'Waypoint';
    }
  }
}

class _SplitRow {
  const _SplitRow({
    required this.name,
    required this.distance,
    required this.color,
    required this.icon,
    required this.offTrack,
    this.cutoff,
  });

  final String name;
  final double distance;
  final Color color;
  final IconData icon;
  final bool offTrack;
  final String? cutoff;
}
