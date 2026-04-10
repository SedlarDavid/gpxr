import 'package:flutter/material.dart';
import '../models/gpx_models.dart';

class WaypointIcons {
  static IconData iconFor(WaypointType type) {
    switch (type) {
      case WaypointType.generic:
        return Icons.flag_rounded;
      case WaypointType.aidStation:
        return Icons.local_cafe_rounded;
      case WaypointType.medical:
        return Icons.medical_services_rounded;
      case WaypointType.water:
        return Icons.water_drop_rounded;
      case WaypointType.food:
        return Icons.restaurant_rounded;
      case WaypointType.summit:
        return Icons.landscape_rounded;
      case WaypointType.camp:
        return Icons.cabin_rounded;
      case WaypointType.parking:
        return Icons.local_parking_rounded;
      case WaypointType.danger:
        return Icons.warning_rounded;
      case WaypointType.info:
        return Icons.info_rounded;
      case WaypointType.start:
        return Icons.play_circle_rounded;
      case WaypointType.finish:
        return Icons.stop_circle_rounded;
    }
  }

  static Color colorFor(WaypointType type) {
    switch (type) {
      case WaypointType.generic:
        return const Color(0xFF6366F1);
      case WaypointType.aidStation:
        return const Color(0xFFF59E0B);
      case WaypointType.medical:
        return const Color(0xFFEF4444);
      case WaypointType.water:
        return const Color(0xFF3B82F6);
      case WaypointType.food:
        return const Color(0xFFF59E0B);
      case WaypointType.summit:
        return const Color(0xFF8B5CF6);
      case WaypointType.camp:
        return const Color(0xFF10B981);
      case WaypointType.parking:
        return const Color(0xFF6B7280);
      case WaypointType.danger:
        return const Color(0xFFEF4444);
      case WaypointType.info:
        return const Color(0xFF06B6D4);
      case WaypointType.start:
        return const Color(0xFF22C55E);
      case WaypointType.finish:
        return const Color(0xFFEF4444);
    }
  }
}
