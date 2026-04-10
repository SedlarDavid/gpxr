import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/gpx_provider.dart';
import '../services/tracedetrail_importer.dart';
import '../utils/theme.dart';

class Toolbar extends StatelessWidget {
  const Toolbar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<GpxProvider>(
      builder: (context, provider, _) {
        return Container(
          height: 56,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: AppTheme.borderColor)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              // Logo / Title
              Row(
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
              const SizedBox(width: 24),
              // File actions
              _ToolbarButton(
                icon: Icons.add_rounded,
                label: 'New',
                onTap: () => _confirmNew(context, provider),
              ),
              const SizedBox(width: 4),
              _ToolbarButton(
                icon: Icons.file_open_rounded,
                label: 'Import',
                onTap: () => _importFile(context, provider),
              ),
              const SizedBox(width: 4),
              _ToolbarButton(
                icon: Icons.public_rounded,
                label: 'Import waypoints from Trace de Trail',
                onTap: provider.hasData
                    ? () => _importTraceDeTrailWaypoints(context, provider)
                    : null,
              ),
              const SizedBox(width: 4),
              _ToolbarButton(
                icon: Icons.download_rounded,
                label: 'Export',
                onTap: provider.hasData
                    ? () => _exportFile(context, provider)
                    : null,
              ),
              const SizedBox(width: 16),
              Container(width: 1, height: 24, color: AppTheme.borderColor),
              const SizedBox(width: 16),
              // Edit tools
              _ToolbarToggle(
                icon: Icons.pan_tool_rounded,
                label: 'View',
                isActive: provider.editMode == EditMode.view,
                onTap: provider.hasData
                    ? () => provider.setEditMode(EditMode.view)
                    : null,
              ),
              const SizedBox(width: 4),
              _ToolbarToggle(
                icon: Icons.add_location_alt_rounded,
                label: 'Add Point',
                isActive: provider.editMode == EditMode.addPoint,
                onTap: provider.hasData
                    ? () => provider.setEditMode(EditMode.addPoint)
                    : null,
              ),
              const SizedBox(width: 4),
              _ToolbarToggle(
                icon: Icons.add_location_rounded,
                label: 'Add Waypoint',
                isActive: provider.editMode == EditMode.addWaypoint,
                onTap: provider.hasData
                    ? () => provider.setEditMode(EditMode.addWaypoint)
                    : null,
              ),
              const SizedBox(width: 4),
              _ToolbarToggle(
                icon: Icons.delete_outline_rounded,
                label: 'Delete',
                isActive: provider.editMode == EditMode.deletePoint,
                onTap: provider.hasData
                    ? () => provider.setEditMode(EditMode.deletePoint)
                    : null,
                activeColor: const Color(0xFFEF4444),
              ),
              const SizedBox(width: 16),
              Container(width: 1, height: 24, color: AppTheme.borderColor),
              const SizedBox(width: 16),
              _ToolbarButton(
                icon: Icons.swap_horiz_rounded,
                label: 'Reverse',
                onTap: provider.hasData ? provider.reverseRoute : null,
              ),
              const Spacer(),
              // Toggles
              if (provider.hasData) ...[
                _ToolbarCheck(
                  icon: Icons.flag_rounded,
                  label: 'Waypoints',
                  isChecked: provider.showWaypoints,
                  onTap: provider.toggleWaypoints,
                ),
                const SizedBox(width: 4),
                _ToolbarCheck(
                  icon: Icons.circle,
                  label: 'Track pts',
                  isChecked: provider.showTrackPoints,
                  onTap: provider.toggleTrackPoints,
                  iconSize: 10,
                ),
              ],
            ],
          ),
        );
      },
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

  void _exportFile(BuildContext context, GpxProvider provider) {
    try {
      final xml = provider.exportToString();
      final bytes = utf8.encode(xml);
      final blob = html.Blob([bytes], 'application/gpx+xml');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final fileName = provider.fileName ?? 'route.gpx';

      html.AnchorElement(href: url)
        ..setAttribute('download', fileName)
        ..click();

      html.Url.revokeObjectUrl(url);

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
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Tooltip(
      message: label,
      child: Material(
        color: Colors.transparent,
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
                  color: enabled
                      ? AppTheme.textPrimary
                      : AppTheme.textSecondary.withValues(alpha: 0.4),
                ),
                if (!compact) ...[
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: enabled
                          ? AppTheme.textPrimary
                          : AppTheme.textSecondary.withValues(alpha: 0.4),
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

class _ToolbarToggle extends StatelessWidget {
  const _ToolbarToggle({
    required this.icon,
    required this.label,
    required this.isActive,
    this.onTap,
    this.activeColor,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback? onTap;
  final Color? activeColor;

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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
  });

  final IconData icon;
  final String label;
  final bool isChecked;
  final VoidCallback onTap;
  final double? iconSize;

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
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: iconSize ?? 14,
                  color: isChecked
                      ? AppTheme.primaryColor
                      : AppTheme.textSecondary.withValues(alpha: 0.4),
                ),
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
            ),
          ),
        ),
      ),
    );
  }
}
