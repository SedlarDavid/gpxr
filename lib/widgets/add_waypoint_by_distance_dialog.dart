import 'package:flutter/material.dart';
import '../models/gpx_models.dart';
import '../providers/gpx_provider.dart';
import '../utils/theme.dart';

/// Opens the "add waypoint by km" dialog and, on confirm, drops the
/// waypoint onto the track at the requested distance via
/// [GpxProvider.addWaypointAtDistance]. Used from the toolbar drawer
/// AND from the waypoint-list empty state so the feature is reachable
/// without hunting in menus.
Future<void> showAddWaypointByDistanceDialog(
  BuildContext context,
  GpxProvider provider,
) async {
  final profile = provider.elevationProfile();
  if (profile.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Load a track first so we know where the km-marks are'),
        backgroundColor: Color(0xFFF59E0B),
      ),
    );
    return;
  }
  final totalKm = profile.totalDistance / 1000;
  final kmController = TextEditingController();
  final nameController = TextEditingController();
  final cutoffController = TextEditingController();
  WaypointType selectedType = WaypointType.aidStation;

  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Add waypoint by km',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Track length: ${totalKm.toStringAsFixed(2)} km',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: kmController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Distance (km)',
                  hintText: 'e.g. 12.5',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Name (optional)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: cutoffController,
                decoration: const InputDecoration(
                  labelText: 'Cutoff (optional)',
                  hintText: '12:30 or 4:15:00',
                ),
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
                    label: Text(type.label),
                    onSelected: (_) => setDialogState(
                      () => selectedType = type,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Add'),
          ),
        ],
      ),
    ),
  );
  if (saved != true) return;
  final km = double.tryParse(kmController.text.replaceAll(',', '.'));
  if (km == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid distance in km')),
      );
    }
    return;
  }
  final cutoff = cutoffController.text.trim();
  provider.addWaypointAtDistance(
    km * 1000,
    name: nameController.text.trim().isEmpty
        ? null
        : nameController.text.trim(),
    type: selectedType,
    cutoff: cutoff.isEmpty ? null : cutoff,
  );
}
