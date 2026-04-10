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
      waypoints.addAll(_toWaypoints(entry.cast<String, dynamic>()));
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

  /// Converts one `dataPi` entry into one or more [GpxWaypoint]s. A single
  /// entry may emit up to three waypoints because Trace de Trail stacks
  /// secondary icons (medical, time checkpoint, text annotation) on top
  /// of the primary one via `type2` / `type3`. We keep them as separate
  /// waypoints so they all show up in the sidebar and survive export.
  List<GpxWaypoint> _toWaypoints(Map<String, dynamic> entry) {
    final abs = _asDouble(entry['abs']);
    final ord = _asDouble(entry['ord']);
    if (abs == null || ord == null) return const [];

    final latLng = _mercatorToLatLng(abs, ord);
    final ele = _asDouble(entry['y']);

    // Pick the best available name. `infobulleTitre` holds the real
    // place name on Trace de Trail; `passageLabel` and `labels` are
    // older/alternate fields kept as fallbacks.
    String? baseName = _firstNonEmpty([
      entry['infobulleTitre'] as String?,
      entry['passageLabel'] as String?,
      entry['labels'] as String?,
    ]);
    // Build a description from the detailed text fields when present —
    // these carry the aid station menu, course instructions, etc.
    final description = _firstNonEmpty([
      entry['infobulleText'] as String?,
      entry['passageDescription'] as String?,
      entry['passageDescription2'] as String?,
    ]);
    // `bh` / `bhd` carry planned ETAs (e.g. start time or cut-off time).
    final bh = (entry['bh'] as String?)?.trim();
    final etaSuffix = (bh != null && bh.isNotEmpty) ? ' · ETA $bh' : '';

    final typeStrs = <String>[
      (entry['type'] as String?)?.toLowerCase().trim() ?? '',
      (entry['type2'] as String?)?.toLowerCase().trim() ?? '',
      (entry['type3'] as String?)?.toLowerCase().trim() ?? '',
    ];

    final waypoints = <GpxWaypoint>[];
    for (int i = 0; i < typeStrs.length; i++) {
      final typeStr = typeStrs[i];
      if (typeStr.isEmpty) continue;
      final wpType = _mapType(typeStr);

      // Primary keeps the clean place name; secondary markers get the
      // type label suffixed so the sidebar distinguishes them even
      // though the coordinates are identical.
      String name;
      if (i == 0) {
        name = (baseName == null || baseName.isEmpty) ? wpType.label : baseName;
      } else {
        name = (baseName == null || baseName.isEmpty)
            ? wpType.label
            : '$baseName (${wpType.label})';
      }
      if (i == 0) name = '$name$etaSuffix';

      waypoints.add(GpxWaypoint(
        latLng: latLng,
        elevation: ele,
        name: name,
        description: i == 0 ? description : null,
        type: wpType,
      ));
    }
    return waypoints;
  }

  static String? _firstNonEmpty(List<String?> candidates) {
    for (final c in candidates) {
      final t = c?.trim();
      if (t != null && t.isNotEmpty) return t;
    }
    return null;
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
      case 'medical':
      case 'infirmerie':
        return WaypointType.medical;
      case 'bh':
      case 'time':
      case 'horaire':
        // Time-of-day checkpoint (planned ETA marker).
        return WaypointType.info;
      case 'text_1':
      case 'text_2':
      case 'text_3':
      case 'text':
        // Free-text annotation rendered as a label on the map.
        return WaypointType.info;
      case 'danger':
      case 'attention':
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
