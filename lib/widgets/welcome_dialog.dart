import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../utils/theme.dart';

/// Key used to remember that the user has dismissed the welcome dialog.
/// Stored in the browser's localStorage — cleared only when the user
/// wipes site data.
const _dismissKey = 'gpxr.welcome.dismissed.v1';

/// URL of the author's tip jar. Empty string hides the button.
const _kofiUrl = 'https://ko-fi.com/sedlardavid';

/// Shows the welcome dialog if the user hasn't dismissed it with
/// "don't show again" on a previous visit. Safe to call unconditionally
/// from the first frame — it bails out quickly when already dismissed.
void maybeShowWelcomeDialog(BuildContext context) {
  final storage = web.window.localStorage;
  if (storage.getItem(_dismissKey) == '1') return;

  showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => const _WelcomeDialog(),
  );
}

class _WelcomeDialog extends StatefulWidget {
  const _WelcomeDialog();

  @override
  State<_WelcomeDialog> createState() => _WelcomeDialogState();
}

class _WelcomeDialogState extends State<_WelcomeDialog> {
  bool _dontShowAgain = false;

  void _close() {
    if (_dontShowAgain) {
      web.window.localStorage.setItem(_dismissKey, '1');
    }
    Navigator.of(context).pop();
  }

  void _openKofi() {
    web.window.open(_kofiUrl, '_blank');
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.subscribe(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = screenWidth < 520 ? screenWidth - 48 : 460.0;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      content: SizedBox(
        width: dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppTheme.primaryColor, AppTheme.trackColorAlt],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.route_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Welcome to GPXR',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'A lightweight GPX route editor for trail runners and hikers. '
              'Plan, tweak and annotate tracks straight in your browser — '
              'no install required.',
              style: TextStyle(fontSize: 13, height: 1.45),
            ),
            const SizedBox(height: 14),
            const _FeatureBullet(
              icon: Icons.edit_location_alt_rounded,
              text: 'Edit tracks and waypoints directly on the map.',
            ),
            const _FeatureBullet(
              icon: Icons.landscape_rounded,
              text:
                  'Interactive elevation profile with climb detection and '
                  'cycling-style category badges.',
            ),
            const _FeatureBullet(
              icon: Icons.public_rounded,
              text:
                  'One-click Trace de Trail waypoint import (Tools → Import '
                  'waypoints from Trace de Trail).',
            ),
            const _FeatureBullet(
              icon: Icons.watch_rounded,
              text: 'Garmin course-point compatible GPX export.',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppTheme.borderColor.withValues(alpha: 0.6),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.favorite_rounded,
                    color: Color(0xFFEF4444),
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'GPXR is free and open source. If it helped you, '
                      'a coffee keeps it maintained.',
                      style: TextStyle(fontSize: 12, height: 1.35),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _openKofi,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF29ABE0),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    icon: const Icon(Icons.local_cafe_rounded, size: 16),
                    label: const Text(
                      'Ko-fi',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Checkbox(
                  value: _dontShowAgain,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (v) => setState(() => _dontShowAgain = v ?? false),
                ),
                const SizedBox(width: 4),
                const Text(
                  "Don't show this again",
                  style: TextStyle(fontSize: 12),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _close,
                  child: const Text('Get started'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureBullet extends StatelessWidget {
  const _FeatureBullet({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    AppTheme.subscribe(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppTheme.primaryColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
