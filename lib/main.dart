import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/gpx_provider.dart';
import 'screens/editor_screen.dart';
import 'utils/theme.dart';

void main() {
  AppTheme.init();
  runApp(const GpxrApp());
}

class GpxrApp extends StatelessWidget {
  const GpxrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => GpxProvider(),
      // ValueListenableBuilder rebuilds the entire MaterialApp when the
      // user flips the brightness toggle in the toolbar — that cascade
      // lets the static AppTheme color getters return the new palette
      // to every widget without us having to thread context through
      // ~170 call sites.
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: AppTheme.themeMode,
        builder: (_, mode, _) => MaterialApp(
          title: 'GPXR - GPX Route Editor',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme(),
          darkTheme: AppTheme.darkTheme(),
          themeMode: mode,
          home: AppThemeScope(child: const EditorScreen()),
        ),
      ),
    );
  }
}
