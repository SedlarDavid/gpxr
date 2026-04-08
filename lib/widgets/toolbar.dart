import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/gpx_provider.dart';
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
            border: Border(
              bottom: BorderSide(color: AppTheme.borderColor),
            ),
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
                        colors: [
                          AppTheme.primaryColor,
                          AppTheme.trackColorAlt,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.route_rounded, color: Colors.white, size: 18),
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
                icon: Icons.download_rounded,
                label: 'Export',
                onTap: provider.hasData ? () => _exportFile(context, provider) : null,
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
        title: const Text('New Route', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        content: const Text('Create a new empty route? Unsaved changes will be lost.'),
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

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final bytes = file.bytes;
        if (bytes != null) {
          final content = utf8.decode(bytes);
          provider.loadFromString(content, file.name);
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
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: enabled ? AppTheme.textPrimary : AppTheme.textSecondary.withValues(alpha: 0.4),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: enabled ? AppTheme.textPrimary : AppTheme.textSecondary.withValues(alpha: 0.4),
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
                  color: isChecked ? AppTheme.primaryColor : AppTheme.textSecondary.withValues(alpha: 0.4),
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isChecked ? AppTheme.textPrimary : AppTheme.textSecondary.withValues(alpha: 0.6),
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
