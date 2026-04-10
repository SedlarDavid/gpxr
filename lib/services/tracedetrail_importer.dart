import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/gpx_models.dart';

/// Imports waypoints (aid stations, food supplies, summits, checkpoints, …)
/// from a tracedetrail.fr race page.
///
/// Trace de Trail's downloadable GPX only contains `<trkpt>` entries — the
/// markers visible on their web map (ravitos, controls, start/finish, …)
/// live in their database and get inlined into the page HTML as a
/// JavaScript variable called `dataPi`. This service scrapes that variable,
/// reprojects the Web Mercator (EPSG:3857) coordinates back to WGS84, and
/// maps each entry to our [GpxWaypoint] model so the user can merge them
/// into an imported GPX.
class TraceDeTrailImporter {
  TraceDeTrailImporter({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// CORS-friendly proxies tried in order until one succeeds. tracedetrail
  /// .fr does not set `Access-Control-Allow-Origin`, so a direct `fetch()`
  /// from another origin is blocked. These public proxies add the needed
  /// headers. Each has gone down occasionally in the past so we keep a
  /// small fallback list.
  static const List<String> _corsProxies = [
    'https://corsproxy.io/?url=',
    'https://api.codetabs.com/v1/proxy/?quest=',
    'https://api.allorigins.win/raw?url=',
  ];

  /// Extracts the trace ID from a tracedetrail.fr URL like
  /// `https://tracedetrail.fr/en/trace/302881`. Returns null for unknown
  /// formats.
  static String? extractTraceId(String input) {
    final trimmed = input.trim();
    final match = RegExp(r'trace/(\d+)').firstMatch(trimmed);
    return match?.group(1);
  }

  Future<List<GpxWaypoint>> fetchWaypoints(String urlOrId) async {
    final id = extractTraceId(urlOrId) ?? urlOrId.trim();
    if (id.isEmpty || !RegExp(r'^\d+$').hasMatch(id)) {
      throw const TraceDeTrailImportException(
        'Enter a tracedetrail.fr URL or numeric trace ID',
      );
    }

    final target = 'https://tracedetrail.fr/fr/trace/$id';
    final body = await _fetchViaProxies(target);
    final raw = _extractDataPi(body);
    if (raw == null) {
      throw const TraceDeTrailImportException(
        'Could not find waypoint data on the page — format may have changed',
      );
    }

    final List<dynamic> decoded;
    try {
      decoded = jsonDecode(raw) as List<dynamic>;
    } on FormatException catch (e) {
      throw TraceDeTrailImportException('Waypoint data was malformed: $e');
    }

    final waypoints = <GpxWaypoint>[];
    for (final entry in decoded) {
      if (entry is! Map) continue;
      final wpt = _toWaypoint(entry.cast<String, dynamic>());
      if (wpt != null) waypoints.add(wpt);
    }
    return waypoints;
  }

  /// Tries each CORS proxy in [_corsProxies] in order until one returns a
  /// 200 response with a non-trivial body. Throws with the most recent
  /// failure message when they all fail.
  Future<String> _fetchViaProxies(String targetUrl) async {
    final encoded = Uri.encodeComponent(targetUrl);
    Object? lastError;
    for (final proxy in _corsProxies) {
      final url = Uri.parse('$proxy$encoded');
      try {
        final response = await _client.get(url);
        if (response.statusCode == 200 && response.body.length > 1000) {
          return response.body;
        }
        lastError = 'HTTP ${response.statusCode} from ${url.host}';
      } catch (e) {
        lastError = '${url.host}: $e';
      }
    }
    throw TraceDeTrailImportException(
      'Could not reach tracedetrail.fr through any CORS proxy (${lastError ?? 'unknown error'})',
    );
  }

  /// The relevant assignment looks like `...,"dataPi":"[{...}]",...` where
  /// the value is a JSON string (so every internal quote is backslash-
  /// escaped). We pull the outer quoted string, then unescape it before
  /// handing it to `jsonDecode`.
  String? _extractDataPi(String html) {
    // The page emits `dataPi:"[{\"piID\":…"` — note the unquoted key
    // (JS object-literal form, not JSON). Accept both quoted and
    // unquoted keys in case the format changes.
    final marker = RegExp(r'"?dataPi"?\s*:\s*"');
    final match = marker.firstMatch(html);
    if (match == null) return null;

    // Walk the escaped string to find the matching closing quote, skipping
    // over `\"` escape sequences. This is more robust than a regex because
    // the value contains arbitrary punctuation.
    final start = match.end;
    int i = start;
    final buf = StringBuffer();
    while (i < html.length) {
      final ch = html[i];
      if (ch == r'\') {
        if (i + 1 >= html.length) break;
        final next = html[i + 1];
        switch (next) {
          case '"':
            buf.write('"');
            break;
          case r'\':
            buf.write(r'\');
            break;
          case '/':
            buf.write('/');
            break;
          case 'n':
            buf.write('\n');
            break;
          case 'r':
            buf.write('\r');
            break;
          case 't':
            buf.write('\t');
            break;
          case 'b':
            buf.write('\b');
            break;
          case 'f':
            buf.write('\f');
            break;
          case 'u':
            if (i + 5 < html.length) {
              final hex = html.substring(i + 2, i + 6);
              final code = int.tryParse(hex, radix: 16);
              if (code != null) buf.writeCharCode(code);
              i += 4;
            }
            break;
          default:
            buf.write(next);
        }
        i += 2;
        continue;
      }
      if (ch == '"') {
        return buf.toString();
      }
      buf.write(ch);
      i++;
    }
    return null;
  }

  GpxWaypoint? _toWaypoint(Map<String, dynamic> entry) {
    final abs = _asDouble(entry['abs']);
    final ord = _asDouble(entry['ord']);
    if (abs == null || ord == null) return null;

    final latLng = _mercatorToLatLng(abs, ord);
    final label = (entry['labels'] as String?)?.trim();
    final typeStr = (entry['type'] as String?)?.toLowerCase().trim() ?? '';
    final wpType = _mapType(typeStr);
    final ele = _asDouble(entry['y']);

    // Synthesize a name when the race page leaves it blank. Falling back
    // to the type label matches what Trace de Trail shows on hover.
    var name = label == null || label.isEmpty ? wpType.label : label;
    // Time-of-day waypoints (`bh`) often have the planned ETA stashed in
    // `bh`; include it in the description so runners see it on the watch.
    final bh = (entry['bh'] as String?)?.trim();
    final description = (bh != null && bh.isNotEmpty && typeStr == 'bh')
        ? 'ETA $bh'
        : null;

    return GpxWaypoint(
      latLng: latLng,
      elevation: ele,
      name: name,
      description: description,
      type: wpType,
    );
  }

  static double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  /// Converts EPSG:3857 (Web Mercator) meters to WGS84 lat/lon.
  static LatLng _mercatorToLatLng(double x, double y) {
    const originShift = 20037508.342789244;
    final lon = (x / originShift) * 180.0;
    var lat = (y / originShift) * 180.0;
    lat = 180 / pi * (2 * atan(exp(lat * pi / 180)) - pi / 2);
    return LatLng(lat, lon);
  }

  /// Maps tracedetrail's internal `type` string to our [WaypointType].
  /// Unknown values fall through to `generic`.
  static WaypointType _mapType(String type) {
    switch (type) {
      case 'depart':
      case 'départ':
        return WaypointType.start;
      case 'arrivee':
      case 'arrivée':
        return WaypointType.finish;
      case 'ravitoc':
      case 'ravito':
      case 'ravitaillement':
        return WaypointType.aidStation;
      case 'eau':
      case 'water':
        return WaypointType.water;
      case 'controle':
      case 'contrôle':
      case 'checkpoint':
        return WaypointType.info;
      case 'sommet':
      case 'summit':
      case 'peak':
        return WaypointType.summit;
      case 'secours':
      case 'rescue':
        return WaypointType.danger;
      case 'camp':
      case 'bivouac':
        return WaypointType.camp;
      case 'parking':
        return WaypointType.parking;
      default:
        return WaypointType.generic;
    }
  }
}

class TraceDeTrailImportException implements Exception {
  const TraceDeTrailImportException(this.message);
  final String message;
  @override
  String toString() => message;
}
