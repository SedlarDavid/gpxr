import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/gpx_provider.dart';
import '../utils/elevation_profile.dart';
import '../utils/geo_utils.dart';
import '../utils/theme.dart';
import '../utils/waypoint_icons.dart';
import 'elevation_profile_chart.dart';
import 'sidebar.dart';

/// Opens the full-screen elevation-profile detail view: a big chart with
/// hover/tap interaction, climbs/splits/waypoints lists below, and no
/// map — for users who want to inspect each section of the route in
/// detail without the map competing for attention.
void showProfileDetailDialog(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => const ProfileDetailView(),
    ),
  );
}

class ProfileDetailView extends StatefulWidget {
  const ProfileDetailView({super.key});

  @override
  State<ProfileDetailView> createState() => _ProfileDetailViewState();
}

class _ProfileDetailViewState extends State<ProfileDetailView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.subscribe(context);
    return Consumer<GpxProvider>(
      builder: (context, provider, _) {
        final data = provider.data;
        if (data == null) {
          // Defensive — caller shouldn't open this without data, but if
          // someone does, fall back to a friendly message instead of
          // crashing on null.
          return Scaffold(
            appBar: AppBar(title: const Text('Elevation profile')),
            body: const Center(child: Text('No track loaded')),
          );
        }

        final profile = provider.elevationProfile();

        final ticks = <WaypointTick>[];
        if (!profile.isEmpty) {
          for (final wpt in data.waypoints) {
            final nearest = profile.nearestOnTrack(wpt.latLng);
            if (nearest == null) continue;
            ticks.add(WaypointTick(
              distance: nearest.distance,
              color: WaypointIcons.colorFor(wpt.type),
              icon: WaypointIcons.iconFor(wpt.type),
              offTrack:
                  nearest.distanceToLineMeters > GpxProvider.snapTolerance,
            ));
          }
        }

        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.white,
            foregroundColor: AppTheme.textPrimary,
            elevation: 0,
            title: Text(
              data.name?.trim().isNotEmpty == true
                  ? data.name!
                  : 'Elevation profile',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            shape: Border(
              bottom: BorderSide(color: AppTheme.borderColor),
            ),
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              // Allocate ~45% of available height to the chart so even
              // on a tall desktop window it stays readable but on
              // phones it doesn't crowd out the lists below.
              final chartHeight =
                  (constraints.maxHeight * 0.45).clamp(220.0, 420.0);
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
                    child: ElevationProfileChart(
                      profile: profile,
                      hoverDistance: provider.hoverDistance,
                      waypointTicks: ticks,
                      height: chartHeight,
                      highlightRange: provider.hoveredClimbRange,
                      descentHighlightRange: provider.hoveredDescentRange,
                    ),
                  ),
                  _HoverReadout(profile: profile, provider: provider),
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
                      Tab(text: 'Climbs'),
                      Tab(text: 'Descents'),
                      Tab(text: 'Splits'),
                      Tab(text: 'Waypoints'),
                    ],
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: const [
                        ClimbsList(),
                        DescentsList(),
                        SplitsList(),
                        WaypointsList(),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// Live readout strip below the chart: distance + elevation at the
/// current hover position. Saves a lot of squinting at a tooltip on
/// long tracks where the pill at the top of the chart can land far
/// from the eye's natural reading position.
class _HoverReadout extends StatelessWidget {
  const _HoverReadout({required this.profile, required this.provider});

  final ElevationProfile profile;
  final GpxProvider provider;

  @override
  Widget build(BuildContext context) {
    AppTheme.subscribe(context);
    return ValueListenableBuilder<double?>(
      valueListenable: provider.hoverDistance,
      builder: (context, d, _) {
        final sample = d != null ? profile.sampleAtDistance(d) : null;
        return Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.centerLeft,
          color: AppTheme.surfaceColor,
          child: Row(
            children: [
              Icon(Icons.straighten_rounded,
                  size: 14, color: AppTheme.textSecondary),
              const SizedBox(width: 6),
              Text(
                sample == null
                    ? '— km'
                    : GeoUtils.formatDistance(sample.distance),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 16),
              Icon(Icons.terrain_rounded,
                  size: 14, color: AppTheme.textSecondary),
              const SizedBox(width: 6),
              Text(
                sample?.elevation == null
                    ? '— m'
                    : '${sample!.elevation!.round()} m',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              Text(
                'Hover or drag the chart to inspect',
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
