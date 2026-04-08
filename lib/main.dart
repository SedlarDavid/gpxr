import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/gpx_provider.dart';
import 'screens/editor_screen.dart';
import 'utils/theme.dart';

void main() {
  runApp(const GpxrApp());
}

class GpxrApp extends StatelessWidget {
  const GpxrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => GpxProvider(),
      child: MaterialApp(
        title: 'GPXR - GPX Route Editor',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme,
        home: const EditorScreen(),
      ),
    );
  }
}
