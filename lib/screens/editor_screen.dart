import 'package:flutter/material.dart';
import '../widgets/map_view.dart';
import '../widgets/sidebar.dart';
import '../widgets/toolbar.dart';

class EditorScreen extends StatelessWidget {
  const EditorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Column(
        children: [
          Toolbar(),
          Expanded(
            child: Row(
              children: [
                Sidebar(),
                Expanded(
                  child: MapView(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
