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
    AppTheme.subscribe(context);
    return Consumer<GpxProvider>(
      builder: (context, provider, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < _compactBreakpoint;
            return Container(
              height: 56,
              decoration: BoxDecoration(
                color: AppTheme.cardColor,
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
          child: const Icon(Icons.route_rounded, color: Colors.white, size: 18),
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
        const _ThemeToggleButton(),
      ],
    );
  }
}

/// Sun/moon brightness toggle pinned to the right edge of the toolbar.
/// Listens to [AppTheme.themeMode] so the icon flips immediately when
/// the mode changes (and stays in sync if it's ever flipped from
/// elsewhere). Persists to localStorage via [AppTheme.toggleMode].
class _ThemeToggleButton extends StatelessWidget {
  const _ThemeToggleButton();

  @override
  Widget build(BuildContext context) {
    AppTheme.subscribe(context);
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppTheme.themeMode,
      builder: (_, mode, _) {
        final dark = mode == ThemeMode.dark;
        return IconButton(
          icon: Icon(dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
          tooltip: dark ? 'Switch to light mode' : 'Switch to dark mode',
          visualDensity: VisualDensity.compact,
          onPressed: AppTheme.toggleMode,
        );
      },
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
    AppTheme.subscribe(context);
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
                            onTap: () =>
                                run((ctx) => _confirmNew(ctx, provider)),
                          ),
                          _DrawerItem(
                            icon: Icons.file_open_rounded,
                            label: 'Import GPX…',
                            onTap: () =>
                                run((ctx) => _importFile(ctx, provider)),
                          ),
                          _DrawerItem(
                            icon: Icons.library_add_rounded,
                            label: 'Merge GPX…',
                            enabled: hasData,
                            onTap: () =>
                                run((ctx) => _appendFiles(ctx, provider)),
                          ),
                          _DrawerItem(
                            icon: Icons.download_rounded,
                            label: 'Export GPX',
                            enabled: hasData,
                            onTap: () =>
                                run((ctx) => _exportFile(ctx, provider)),
                          ),
                          _DrawerItem(
                            icon: Icons.watch_rounded,
                            label: 'Export FIT (Garmin course)',
                            enabled: hasData,
                            onTap: () =>
                                run((ctx) => _exportFitFile(ctx, provider)),
                          ),
                          _DrawerItem(
                            icon: Icons.download_for_offline_rounded,
                            label: 'Export TCX (legacy)',
                            enabled: hasData,
                            onTap: () =>
                                run((ctx) => _exportTcxFile(ctx, provider)),
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
                              (ctx) => _autoWaypointsFromClimbs(ctx, provider),
                            ),
                          ),
                          _DrawerItem(
                            icon: Icons.public_rounded,
                            label: 'Import from Trace de Trail…',
                            enabled: hasData,
                            onTap: () => run(
                              (ctx) =>
                                  _importTraceDeTrailWaypoints(ctx, provider),
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
    AppTheme.subscribe(context);
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
    AppTheme.subscribe(context);
    final fg = enabled
        ? AppTheme.textPrimary
        : AppTheme.textSecondary.withValues(alpha: 0.4);
    return ListTile(
      leading: Icon(icon, size: 20, color: fg),
      title: Text(
        label,
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: fg),
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
      content: Text('Added $added summit waypoint${added == 1 ? '' : 's'}'),
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
  final controller = _LoadingController(context);
  try {
    // Show the dialog BEFORE opening the picker. The OS picker will
    // sit on top of it while it's open, but the moment the user
    // confirms (or cancels) and the picker dismisses, our dialog is
    // already mounted and visible — covering the silent file_picker
    // bytes-read phase that previously showed no feedback at all.
    // We await an actual frame so the dialog is painted before the
    // synchronous picker call yields control.
    controller.show('Opening file…');
    await WidgetsBinding.instance.endOfFrame;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gpx', 'xml'],
      withData: true,
      // Multi-pick lets the user load a multi-day trip in one go: the
      // first file replaces whatever's loaded, and the rest get
      // merged in as additional tracks with their own colors.
      allowMultiple: true,
      onFileLoading: (status) {
        if (status == FilePickerStatus.picking) {
          controller.update('Reading file…');
        }
      },
    );

    if (result == null || result.files.isEmpty) return;
    final files = result.files.where((f) => f.bytes != null).toList();
    if (files.isEmpty) return;
    if (!context.mounted) return;

    final firstFile = files.first;
    await controller.runTask(
      message: files.length == 1
          ? 'Parsing ${firstFile.name}…'
          : 'Parsing 1 of ${files.length}: ${firstFile.name}…',
      task: () async {
        final content = utf8.decode(firstFile.bytes!);
        provider.loadFromString(content, firstFile.name);
        for (int i = 1; i < files.length; i++) {
          final f = files[i];
          controller.update('Parsing ${i + 1} of ${files.length}: ${f.name}…');
          // Yield a frame between files so the message visibly
          // updates instead of jumping from "1 of 4" straight to
          // dismissed when the loop finishes.
          await WidgetsBinding.instance.endOfFrame;
          final c = utf8.decode(f.bytes!);
          provider.appendFromString(c, f.name);
        }
      },
    );

    // Detect sources we know how to enrich and offer an auto-import.
    // Skip when we merged multiple files — the prompt assumes one
    // primary source URL and the user is in bulk-load mode anyway.
    if (!context.mounted) return;
    if (files.length == 1) {
      final sourceUrl = provider.data?.sourceUrl;
      if (sourceUrl != null &&
          TraceDeTrailImporter.extractTraceId(sourceUrl) != null) {
        final accepted = await _askEnrichFromTraceDeTrail(context, sourceUrl);
        if (accepted == true && context.mounted) {
          await _fetchAndImportWaypoints(context, provider, sourceUrl);
        }
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
  } finally {
    controller.dismiss();
    controller.dispose();
  }
}

/// Picks one or more GPX files and merges every track into the
/// currently loaded data without replacing it. Falls back to a
/// regular import when nothing is loaded yet.
Future<void> _appendFiles(BuildContext context, GpxProvider provider) async {
  if (!provider.hasData) {
    await _importFile(context, provider);
    return;
  }
  final controller = _LoadingController(context);
  try {
    controller.show('Opening file…');
    await WidgetsBinding.instance.endOfFrame;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gpx', 'xml'],
      withData: true,
      allowMultiple: true,
      onFileLoading: (status) {
        if (status == FilePickerStatus.picking) {
          controller.update('Reading file…');
        }
      },
    );
    if (result == null || result.files.isEmpty) return;
    final files = result.files.where((f) => f.bytes != null).toList();
    if (files.isEmpty) return;
    if (!context.mounted) return;
    int added = 0;
    await controller.runTask(
      message: files.length == 1
          ? 'Merging ${files.first.name}…'
          : 'Merging 1 of ${files.length}: ${files.first.name}…',
      task: () async {
        for (int i = 0; i < files.length; i++) {
          final f = files[i];
          if (i > 0) {
            controller.update(
              'Merging ${i + 1} of ${files.length}: ${f.name}…',
            );
            await WidgetsBinding.instance.endOfFrame;
          }
          final c = utf8.decode(f.bytes!);
          added += provider.appendFromString(c, f.name);
        }
      },
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Merged $added track${added == 1 ? '' : 's'} '
          'from ${files.length} file${files.length == 1 ? '' : 's'}',
        ),
        backgroundColor: const Color(0xFF22C55E),
        duration: const Duration(seconds: 3),
      ),
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to merge file: $e'),
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
  final controller = _LoadingController(context);
  try {
    await controller.runTask(
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
  } finally {
    controller.dismiss();
    controller.dispose();
  }

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
    final fileName = _gpxFileName(provider.fileName);

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

void _exportFitFile(BuildContext context, GpxProvider provider) {
  try {
    final bytes = provider.exportFitToBytes();
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'application/vnd.ant.fit'),
    );
    final url = web.URL.createObjectURL(blob);
    final fileName = _fitFileName(provider.fileName);

    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = fileName;
    anchor.click();

    web.URL.revokeObjectURL(url);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'FIT course exported — upload to Garmin Connect → Training → Courses → Import',
        ),
        backgroundColor: Color(0xFF22C55E),
        duration: Duration(seconds: 4),
      ),
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Failed to export FIT: $e'),
        backgroundColor: const Color(0xFFEF4444),
      ),
    );
  }
}

String _fitFileName(String? source) {
  final raw = (source ?? '').trim();
  if (raw.isEmpty) return 'course.fit';
  final dot = raw.lastIndexOf('.');
  final stem = dot > 0 ? raw.substring(0, dot) : raw;
  final clean = stem.trim().isEmpty ? 'course' : stem.trim();
  return '$clean.fit';
}

void _exportTcxFile(BuildContext context, GpxProvider provider) {
  try {
    final xml = provider.exportTcxToString();
    final bytes = utf8.encode(xml);
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'application/vnd.garmin.tcx+xml'),
    );
    final url = web.URL.createObjectURL(blob);
    final fileName = _tcxFileName(provider.fileName);

    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = fileName;
    anchor.click();

    web.URL.revokeObjectURL(url);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('TCX file exported — upload to Garmin Connect as course'),
        backgroundColor: Color(0xFF22C55E),
        duration: Duration(seconds: 3),
      ),
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Failed to export TCX: $e'),
        backgroundColor: const Color(0xFFEF4444),
      ),
    );
  }
}

String _tcxFileName(String? source) {
  final raw = (source ?? '').trim();
  if (raw.isEmpty) return 'course.tcx';
  final dot = raw.lastIndexOf('.');
  final stem = dot > 0 ? raw.substring(0, dot) : raw;
  final clean = stem.trim().isEmpty ? 'course' : stem.trim();
  return '$clean.tcx';
}

/// Forces a `.gpx` extension regardless of the source filename. Prevents
/// re-exporting a file imported as `route.xml` from going back out as
/// `route.xml`, which leaves users wondering why the download isn't a
/// real GPX.
String _gpxFileName(String? source) {
  final raw = (source ?? '').trim();
  if (raw.isEmpty) return 'route.gpx';
  final dot = raw.lastIndexOf('.');
  final stem = dot > 0 ? raw.substring(0, dot) : raw;
  final clean = stem.trim().isEmpty ? 'route' : stem.trim();
  return '$clean.gpx';
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
    AppTheme.subscribe(context);
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
    AppTheme.subscribe(context);
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

/// Controls a single modal loading dialog whose message can be updated
/// while the dialog is on screen. Used by the import flows so the user
/// gets continuous feedback through the three phases that can each
/// take seconds (file read, parse, optional remote enrichment) without
/// the dialog flashing in and out between them.
class _LoadingController {
  _LoadingController(this._context);

  final BuildContext _context;
  final ValueNotifier<String> _message = ValueNotifier<String>('Loading…');
  bool _shown = false;
  bool _disposed = false;

  /// Shows the dialog with [message] if it isn't on screen yet, or
  /// just updates the message when it already is. Safe to call
  /// repeatedly; the dialog only mounts once per controller.
  void show(String message) {
    _message.value = message;
    if (_shown || _disposed || !_context.mounted) return;
    _shown = true;
    showDialog<void>(
      context: _context,
      barrierDismissible: false,
      builder: (_) => ValueListenableBuilder<String>(
        valueListenable: _message,
        builder: (_, m, _) => _LoadingDialog(message: m),
      ),
    );
  }

  /// Updates the visible message. No-op if the dialog hasn't been
  /// shown yet (call [show] first).
  void update(String message) {
    _message.value = message;
  }

  /// Shows the dialog (if not already), waits for the engine to
  /// actually paint a frame so the spinner appears before [task]
  /// starts, then runs [task]. The wait matters: a synchronous XML
  /// parse on the main thread will otherwise start before the dialog
  /// renders, leaving the user staring at a frozen UI for seconds.
  Future<void> runTask({
    required String message,
    required Future<void> Function() task,
  }) async {
    show(message);
    // First endOfFrame: the dialog widget tree is built and laid out.
    // Second endOfFrame: pixels are actually presented to the canvas.
    // The microtask yield in between handles the case where the
    // engine was mid-frame when showDialog requested a build.
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(Duration.zero);
    await WidgetsBinding.instance.endOfFrame;
    await task();
  }

  void dismiss() {
    if (!_shown || _disposed) return;
    _shown = false;
    if (_context.mounted) {
      Navigator.of(_context, rootNavigator: true).pop();
    }
  }

  void dispose() {
    _disposed = true;
    _message.dispose();
  }
}

class _LoadingDialog extends StatelessWidget {
  const _LoadingDialog({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    AppTheme.subscribe(context);
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
              child: Text(message, style: const TextStyle(fontSize: 13)),
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
    AppTheme.subscribe(context);
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
