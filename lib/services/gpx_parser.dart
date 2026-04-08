import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';
import '../models/gpx_models.dart';

class GpxParser {
  GpxData parse(String xmlString) {
    final document = XmlDocument.parse(xmlString);
    final gpx = document.rootElement;

    final name = _textOf(gpx, 'name');
    final description = _textOf(gpx, 'desc');
    final authorEl = gpx.getElement('author');
    final author = authorEl != null ? _textOf(authorEl, 'name') : null;

    final waypoints = gpx
        .findElements('wpt')
        .map(_parseWaypoint)
        .toList();

    final tracks = gpx
        .findElements('trk')
        .map(_parseTrack)
        .toList();

    final routes = gpx
        .findElements('rte')
        .map(_parseRoute)
        .toList();

    return GpxData(
      name: name,
      description: description,
      author: author,
      waypoints: waypoints,
      tracks: tracks,
      routes: routes,
    );
  }

  String export(GpxData data) {
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element('gpx', nest: () {
      builder.attribute('version', '1.1');
      builder.attribute('creator', 'GPXR Editor');
      builder.attribute('xmlns', 'http://www.topografix.com/GPX/1/1');
      builder.attribute(
        'xmlns:xsi', 'http://www.w3.org/2001/XMLSchema-instance');
      builder.attribute('xsi:schemaLocation',
        'http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd');

      if (data.name != null) {
        builder.element('metadata', nest: () {
          builder.element('name', nest: data.name);
          if (data.description != null) {
            builder.element('desc', nest: data.description);
          }
          if (data.author != null) {
            builder.element('author', nest: () {
              builder.element('name', nest: data.author);
            });
          }
        });
      }

      for (final wpt in data.waypoints) {
        _buildWaypoint(builder, wpt);
      }

      for (final route in data.routes) {
        builder.element('rte', nest: () {
          if (route.name != null) {
            builder.element('name', nest: route.name);
          }
          for (final pt in route.points) {
            _buildTrackPoint(builder, pt, 'rtept');
          }
        });
      }

      for (final track in data.tracks) {
        builder.element('trk', nest: () {
          if (track.name != null) {
            builder.element('name', nest: track.name);
          }
          for (final seg in track.segments) {
            builder.element('trkseg', nest: () {
              for (final pt in seg.points) {
                _buildTrackPoint(builder, pt, 'trkpt');
              }
            });
          }
        });
      }
    });

    return builder.buildDocument().toXmlString(pretty: true);
  }

  GpxWaypoint _parseWaypoint(XmlElement el) {
    final lat = double.parse(el.getAttribute('lat')!);
    final lon = double.parse(el.getAttribute('lon')!);
    final ele = _doubleOf(el, 'ele');
    final name = _textOf(el, 'name');
    final desc = _textOf(el, 'desc');
    final sym = _textOf(el, 'sym');
    final timeStr = _textOf(el, 'time');

    return GpxWaypoint(
      latLng: LatLng(lat, lon),
      elevation: ele,
      name: name,
      description: desc,
      type: WaypointType.fromSym(sym),
      time: timeStr != null ? DateTime.tryParse(timeStr) : null,
    );
  }

  GpxTrack _parseTrack(XmlElement el) {
    final name = _textOf(el, 'name');
    final segments = el
        .findElements('trkseg')
        .map((seg) {
          final points = seg
              .findElements('trkpt')
              .map(_parseTrackPoint)
              .toList();
          return GpxTrackSegment(points: points);
        })
        .toList();

    return GpxTrack(name: name, segments: segments);
  }

  GpxRoute _parseRoute(XmlElement el) {
    final name = _textOf(el, 'name');
    final points = el
        .findElements('rtept')
        .map(_parseTrackPoint)
        .toList();

    return GpxRoute(name: name, points: points);
  }

  GpxTrackPoint _parseTrackPoint(XmlElement el) {
    final lat = double.parse(el.getAttribute('lat')!);
    final lon = double.parse(el.getAttribute('lon')!);
    final ele = _doubleOf(el, 'ele');
    final timeStr = _textOf(el, 'time');

    return GpxTrackPoint(
      latLng: LatLng(lat, lon),
      elevation: ele,
      time: timeStr != null ? DateTime.tryParse(timeStr) : null,
    );
  }

  void _buildWaypoint(XmlBuilder builder, GpxWaypoint wpt) {
    builder.element('wpt', nest: () {
      builder.attribute('lat', wpt.latLng.latitude.toString());
      builder.attribute('lon', wpt.latLng.longitude.toString());
      if (wpt.elevation != null) {
        builder.element('ele', nest: wpt.elevation.toString());
      }
      if (wpt.time != null) {
        builder.element('time', nest: wpt.time!.toUtc().toIso8601String());
      }
      if (wpt.name != null) {
        builder.element('name', nest: wpt.name);
      }
      if (wpt.description != null) {
        builder.element('desc', nest: wpt.description);
      }
      builder.element('sym', nest: wpt.type.sym);
    });
  }

  void _buildTrackPoint(XmlBuilder builder, GpxTrackPoint pt, String tag) {
    builder.element(tag, nest: () {
      builder.attribute('lat', pt.latLng.latitude.toString());
      builder.attribute('lon', pt.latLng.longitude.toString());
      if (pt.elevation != null) {
        builder.element('ele', nest: pt.elevation.toString());
      }
      if (pt.time != null) {
        builder.element('time', nest: pt.time!.toUtc().toIso8601String());
      }
    });
  }

  String? _textOf(XmlElement parent, String name) {
    final el = parent.getElement(name);
    return el?.innerText.isEmpty == true ? null : el?.innerText;
  }

  double? _doubleOf(XmlElement parent, String name) {
    final text = _textOf(parent, name);
    return text != null ? double.tryParse(text) : null;
  }
}
