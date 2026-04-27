import 'dart:convert';
import 'dart:js_interop';

import 'package:file_picker/file_picker.dart';
import 'package:web/web.dart' as web;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/gpx_models.dart';
import '../providers/gpx_provider.dart';
import '../services/tracedetrail_importer.dart';
import '../utils/theme.dart';
import 'add_waypoint_by_distance_dialog.dart';

/// Width below which edit-mode toggles drop their text labels and stay
/// icon-only. The toolbar middle row is always horizontally scrollable
/// so it can never overflow regardless of width.
const double _compactBreakpoint = 760;

class Toolbar extends StatelessWidget {
  const Toolbar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<GpxProvider>(
      builder: (context, provider, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < _compactBreakpoint;
            return Container(
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: AppTheme.borderColor)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _buildToolbarContent(context, provider, compact),
            );
          },
        );
      },
    );
  }

  Widget _buildToolbarContent(
    BuildContext context,
    GpxProvider provider,
    bool compact,
  ) {
    final smallGap = SizedBox(width: compact ? 2 : 4);

    // Hamburger opens the Scaffold drawer where file ops + bulk tools
    // live. Keeping the toolbar slim was the user's explicit ask — too
    // many top-bar icons were overflowing on mid-width windows.
    final hamburger = Builder(
      builder: (ctx) => IconButton(
        icon: const Icon(Icons.menu_rounded),
        tooltip: 'Menu',
        visualDensity: VisualDensity.compact,
        onPressed: () => Scaffold.of(ctx).openDrawer(),
      ),
    );

    final logo = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppTheme.primaryColor, AppTheme.trackColorAlt],
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.route_rounded,
            color: Colors.white,
            size: 18,
          ),
        ),
        if (!compact) ...[
          const SizedBox(width: 10),
          const Text(
            'GPXR',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ],
    );

    // Edit mode toggles + activity + visibility — these stay in the
    // toolbar because they're the actions used multiple times per
    // editing session. Wrapped in a horizontal scroll view so we can
    // never overflow even on cramped widths.
    final scrollableMiddle = Expanded(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _ToolbarToggle(
              icon: Icons.pan_tool_rounded,
              label: 'View',
              isActive: provider.editMode == EditMode.view,
              onTap: provider.hasData
                  ? () => provider.setEditMode(EditMode.view)
                  : null,
              compact: compact,
            ),
            smallGap,
            _ToolbarToggle(
              icon: Icons.add_location_alt_rounded,
              label: 'Add Point',
              isActive: provider.editMode == EditMode.addPoint,
              onTap: provider.hasData
                  ? () => provider.setEditMode(EditMode.addPoint)
                  : null,
              compact: compact,
            ),
            smallGap,
            _ToolbarToggle(
              icon: Icons.add_location_rounded,
              label: 'Add Waypoint',
              isActive: provider.editMode == EditMode.addWaypoint,
              onTap: provider.hasData
                  ? () => provider.setEditMode(EditMode.addWaypoint)
                  : null,
              compact: compact,
            ),
            smallGap,
            _ToolbarToggle(
              icon: Icons.delete_outline_rounded,
              label: 'Delete',
              isActive: provider.editMode == EditMode.deletePoint,
              onTap: provider.hasData
                  ? () => provider.setEditMode(EditMode.deletePoint)
                  : null,
              activeColor: const Color(0xFFEF4444),
              compact: compact,
            ),
            const SizedBox(width: 12),
            Container(width: 1, height: 24, color: AppTheme.borderColor),
            const SizedBox(width: 12),
            _ActivityToggle(
              current: provider.activityType,
              onChanged: provider.setActivityType,
              compact: compact,
            ),
            if (provider.hasData) ...[
              const SizedBox(width: 12),
              Container(width: 1, height: 24, color: AppTheme.borderColor),
              const SizedBox(width: 12),
              _ToolbarCheck(
                icon: Icons.flag_rounded,
                label: 'Waypoints',
                isChecked: provider.showWaypoints,
                onTap: provider.toggleWaypoints,
                compact: compact,
              ),
              smallGap,
              _ToolbarCheck(
                icon: Icons.circle,
                label: 'Track pts',
                isChecked: provider.showTrackPoints,
                onTap: provider.toggleTrackPoints,
                iconSize: 10,
                compact: compact,
              ),
            ],
          ],
        ),
      ),
    );

    return Row(
      children: [
        hamburger,
        const SizedBox(width: 4),
        logo,
        const SizedBox(width: 12),
        scrollableMiddle,
      ],
    );
  }
}

/// Side drawer hosting the file actions (new / import / export) and the
/// bulk-edit tools (Trace de Trail import, auto-waypoints from climbs,
/// reverse, request feature). Toolbar opens it via a hamburger so the
/// top bar stays slim — too many top-bar actions were the user's
/// explicit complaint.
class GpxDrawer extends StatelessWidget {
  const GpxDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<GpxProvider>(
      builder: (context, provider, _) {
        final hasData = provider.hasData;
        return Drawer(
          width: 320,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppTheme.primaryColor,
                              AppTheme.trackColorAlt,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.route_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'GPXR',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: Builder(
                    builder: (drawerContext) {
                      // Pop the drawer first, then run the action on the
                      // ROOT navigator's context. The drawer's own
                      // BuildContext is unmounted as soon as we pop, so
                      // any async work that checks `context.mounted`
                      // (file picker, snackbar, showDialog) silently
                      // bailed out — that's why "Import GPX" did
                      // nothing after the file picker closed.
                      void run(void Function(BuildContext rootCtx) action) {
                        final rootCtx = Navigator.of(
                          drawerContext,
                          rootNavigator: true,
                        ).context;
                        Navigator.of(drawerContext).pop();
                        action(rootCtx);
                      }

                      return ListView(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        children: [
                          _DrawerSection(label: 'File'),
                          _DrawerItem(
                            icon: Icons.add_rounded,
                            label: 'New route',
                            onTap: () => run(
                              (ctx) => _confirmNew(ctx, provider),
                            ),
                          ),
                          _DrawerItem(
                            icon: Icons.file_open_rounded,
                            label: 'Import GPX…',
                            onTap: () => run(
                              (ctx) => _importFile(ctx, provider),
                            ),
                          ),
                          _DrawerItem(
                            icon: Icons.download_rounded,
                            label: 'Export GPX',
                            enabled: hasData,
                            onTap: () => run(
                              (ctx) => _exportFile(ctx, provider),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _DrawerSection(label: 'Waypoints'),
                          _DrawerItem(
                            icon: Icons.straighten_rounded,
                            label: 'Add by km…',
                            enabled: hasData,
                            onTap: () => run(
                              (ctx) => showAddWaypointByDistanceDialog(
                                ctx,
                                provider,
                              ),
                            ),
                          ),
                          _DrawerItem(
                            icon: Icons.landscape_rounded,
                            label: 'Auto-create from climbs',
                            enabled: hasData,
                            onTap: () => run(
                              (ctx) => _autoWaypointsFromClimbs(
                                ctx,
                                provider,
                              ),
                            ),
                          ),
                          _DrawerItem(
                            icon: Icons.public_rounded,
                            label: 'Import from Trace de Trail…',
                            enabled: hasData,
                            onTap: () => run(
                              (ctx) => _importTraceDeTrailWaypoints(
                                ctx,
                                provider,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _DrawerSection(label: 'Route'),
                          _DrawerItem(
                            icon: Icons.swap_horiz_rounded,
                            label: 'Reverse direction',
                            enabled: hasData,
                            onTap: () => run((_) => provider.reverseRoute()),
                          ),
                          const SizedBox(height: 8),
                          const Divider(height: 1),
                          _DrawerItem(
                            icon: Icons.lightbulb_outline_rounded,
                            label: 'Request a feature',
                            onTap: () => run((_) => _openFeatureRequest()),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DrawerSection extends StatelessWidget {
  const _DrawerSection({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final fg = enabled
        ? AppTheme.textPrimary
        : AppTheme.textSecondary.withValues(alpha: 0.4);
    return ListTile(
      leading: Icon(icon, size: 20, color: fg),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: fg,
        ),
      ),
      onTap: enabled ? onTap : null,
      dense: true,
      visualDensity: VisualDensity.compact,
    );
  }
}

Future<void> _autoWaypointsFromClimbs(
  BuildContext context,
  GpxProvider provider,
) async {
    final added = provider.autoWaypointsFromClimbs();
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (added == 0) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No new climbs found to mark'),
          backgroundColor: Color(0xFFF59E0B),
        ),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Added $added summit waypoint${added == 1 ? '' : 's'}',
        ),
        backgroundColor: const Color(0xFF22C55E),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _confirmNew(BuildContext context, GpxProvider provider) {
    if (!provider.hasData) {
      provider.createNew();
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'New Route',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        content: const Text(
          'Create a new empty route? Unsaved changes will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              provider.createNew();
              Navigator.pop(ctx);
            },
            child: const Text('Create New'),
          ),
        ],
      ),
    );
  }

  Future<void> _importFile(BuildContext context, GpxProvider provider) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['gpx', 'xml'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) return;
      if (!context.mounted) return;

      // Parsing a 50 km+ GPX takes long enough on the web to feel frozen,
      // so show a blocking loading dialog while we decode + parse. The
      // Future.delayed yields one frame so the dialog actually paints
      // before the synchronous parse starts.
      await _runWithLoading(
        context,
        message: 'Parsing ${file.name}…',
        task: () async {
          await Future<void>.delayed(Duration.zero);
          final content = utf8.decode(bytes);
          provider.loadFromString(content, file.name);
        },
      );

      // Detect sources we know how to enrich and offer an auto-import.
      if (!context.mounted) return;
      final sourceUrl = provider.data?.sourceUrl;
      if (sourceUrl != null &&
          TraceDeTrailImporter.extractTraceId(sourceUrl) != null) {
        final accepted = await _askEnrichFromTraceDeTrail(context, sourceUrl);
        if (accepted == true && context.mounted) {
          await _fetchAndImportWaypoints(context, provider, sourceUrl);
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to import file: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  /// Shown after a GPX file is loaded when we detect the source is a
  /// Trace de Trail race page. Tells the user what's about to happen
  /// and lets them opt out — returning false keeps the track as-is.
  Future<bool?> _askEnrichFromTraceDeTrail(
    BuildContext context,
    String sourceUrl,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Trace de Trail detected',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "This GPX was exported from Trace de Trail, which strips "
                "the waypoints (aid stations, medical points, checkpoints, "
                "time controls…) when you download it. We can fetch them "
                "straight from the race page and snap them onto your track.",
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 10),
              SelectableText(
                sourceUrl,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF6B7280),
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Skip'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Import waypoints'),
          ),
        ],
      ),
    );
  }

  Future<void> _importTraceDeTrailWaypoints(
    BuildContext context,
    GpxProvider provider,
  ) async {
    final urlController = TextEditingController(
      text: provider.data?.sourceUrl ?? '',
    );
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Import waypoints from Trace de Trail',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Trace de Trail's downloadable GPX doesn't include aid "
                'stations or checkpoints. Paste the race page URL to pull '
                'them in and snap them onto your track.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Race page URL',
                  hintText: 'https://tracedetrail.fr/en/trace/302881',
                ),
                onSubmitted: (v) => Navigator.pop(ctx, v),
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
            onPressed: () => Navigator.pop(ctx, urlController.text),
            child: const Text('Import'),
          ),
        ],
      ),
    );

    if (result == null || result.trim().isEmpty) return;
    if (!context.mounted) return;
    await _fetchAndImportWaypoints(context, provider, result);
  }

  /// Shared fetch-and-merge pipeline used by both the manual URL dialog
  /// and the auto-detection path triggered after a file import. Shows a
  /// blocking loading dialog while the network call is in flight and
  /// surfaces success / error as a snackbar once it's done.
  Future<void> _fetchAndImportWaypoints(
    BuildContext context,
    GpxProvider provider,
    String urlOrId,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    int? added;
    Object? error;
    await _runWithLoading(
      context,
      message: 'Fetching waypoints from Trace de Trail…',
      task: () async {
        try {
          final importer = TraceDeTrailImporter();
          final waypoints = await importer.fetchWaypoints(urlOrId);
          added = provider.importWaypoints(waypoints);
        } catch (e) {
          error = e;
        }
      },
    );

    if (error != null) {
      final msg = error is TraceDeTrailImportException
          ? (error as TraceDeTrailImportException).message
          : error.toString();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Import failed: $msg'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
      return;
    }
    if (added == 0) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No waypoints found on that page'),
          backgroundColor: Color(0xFFF59E0B),
        ),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text('Imported $added waypoint${added == 1 ? '' : 's'}'),
        backgroundColor: const Color(0xFF22C55E),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Shows a modal spinner while [task] runs and guarantees the dialog
  /// is dismissed even if the task throws. The dialog is barrier-
  /// dismissible-false so the user can't accidentally cancel mid-parse.
  Future<void> _runWithLoading(
    BuildContext context, {
    required String message,
    required Future<void> Function() task,
  }) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _LoadingDialog(message: message),
    );
    try {
      await task();
    } finally {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  void _openFeatureRequest() {
    web.window.open(
      'https://github.com/SedlarDavid/gpxr/issues/new'
          '?labels=enhancement'
          '&title=Feature%20request%3A%20',
      '_blank',
    );
  }

  void _exportFile(BuildContext context, GpxProvider provider) {
    try {
      final xml = provider.exportToString();
      final bytes = utf8.encode(xml);
      final blob = web.Blob(
        [bytes.toJS].toJS,
        web.BlobPropertyBag(type: 'application/gpx+xml'),
      );
      final url = web.URL.createObjectURL(blob);
      final fileName = provider.fileName ?? 'route.gpx';

      final anchor = web.HTMLAnchorElement()
        ..href = url
        ..download = fileName;
      anchor.click();

      web.URL.revokeObjectURL(url);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('GPX file exported successfully'),
          backgroundColor: Color(0xFF22C55E),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to export: $e'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  }

class _ActivityToggle extends StatelessWidget {
  const _ActivityToggle({
    required this.current,
    required this.onChanged,
    this.compact = false,
  });

  final ActivityType current;
  final ValueChanged<ActivityType> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message:
          'Activity type — drives climb grading and grade colors. '
          'Trail running uses steeper thresholds than cycling.',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: PopupMenuButton<ActivityType>(
          tooltip: '',
          position: PopupMenuPosition.under,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          onSelected: onChanged,
          itemBuilder: (ctx) => [
            for (final t in ActivityType.values)
              CheckedPopupMenuItem<ActivityType>(
                value: t,
                checked: current == t,
                child: Row(
                  children: [
                    Icon(
                      t == ActivityType.bike
                          ? Icons.directions_bike_rounded
                          : Icons.directions_run_rounded,
                      size: 16,
                      color: AppTheme.textPrimary,
                    ),
                    const SizedBox(width: 10),
                    Text(t.label),
                  ],
                ),
              ),
          ],
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 10,
              vertical: 6,
            ),
            child: Row(
              children: [
                Icon(
                  current == ActivityType.bike
                      ? Icons.directions_bike_rounded
                      : Icons.directions_run_rounded,
                  size: 16,
                  color: AppTheme.primaryColor,
                ),
                if (!compact) ...[
                  const SizedBox(width: 6),
                  Text(
                    current.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  Icon(
                    Icons.arrow_drop_down_rounded,
                    size: 18,
                    color: AppTheme.textSecondary,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolbarToggle extends StatelessWidget {
  const _ToolbarToggle({
    required this.icon,
    required this.label,
    required this.isActive,
    this.onTap,
    this.activeColor,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback? onTap;
  final Color? activeColor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final color = activeColor ?? AppTheme.primaryColor;

    return Tooltip(
      message: label,
      child: Material(
        color: isActive ? color.withValues(alpha: 0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 10,
              vertical: 6,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: !enabled
                      ? AppTheme.textSecondary.withValues(alpha: 0.4)
                      : isActive
                      ? color
                      : AppTheme.textSecondary,
                ),
                if (!compact) ...[
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                      color: !enabled
                          ? AppTheme.textSecondary.withValues(alpha: 0.4)
                          : isActive
                          ? color
                          : AppTheme.textPrimary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingDialog extends StatelessWidget {
  const _LoadingDialog({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: SizedBox(
        width: 280,
        child: Row(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarCheck extends StatelessWidget {
  const _ToolbarCheck({
    required this.icon,
    required this.label,
    required this.isChecked,
    required this.onTap,
    this.iconSize,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final bool isChecked;
  final VoidCallback onTap;
  final double? iconSize;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '${isChecked ? "Hide" : "Show"} $label',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 6 : 8,
              vertical: 6,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: iconSize ?? 14,
                  color: isChecked
                      ? AppTheme.primaryColor
                      : AppTheme.textSecondary.withValues(alpha: 0.4),
                ),
                if (!compact) ...[
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isChecked
                          ? AppTheme.textPrimary
                          : AppTheme.textSecondary.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
