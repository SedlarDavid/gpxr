# GPXR — GPX Route Editor

[![Live demo](https://img.shields.io/badge/demo-gpxr.sedlardavid.cz-6366F1)](https://gpxr.sedlardavid.cz)
[![License: MIT](https://img.shields.io/badge/license-MIT-22c55e)](LICENSE)
[![Built with Flutter](https://img.shields.io/badge/built%20with-Flutter-02569B?logo=flutter)](https://flutter.dev)

A lightweight GPX route editor for the web, built with Flutter. Designed
for trail runners, hikers and cyclists who want to plan, tweak and
annotate GPX tracks from their browser without installing anything.
Tracks are parsed, edited and exported entirely client-side — your
files never leave your browser. Works on desktop and mobile.

**Live at <https://gpxr.sedlardavid.cz>.**

## Features

### Route editing
- Import and export GPX files
- Add, move, delete and reorder track points directly on the map
- Reverse route direction in one click
- Smart insert: click near the track and the new point is placed on
  the closest segment instead of at the end
- Responsive layout: side-by-side editor on desktop, draggable bottom
  panel on phones

### Waypoints
- Rich set of built-in types: aid station, medical, water, food,
  summit, camp, parking, info, danger, start, finish, generic
- Snap-to-track on click or drop so waypoints line up exactly with the
  course (Garmin course-point compatible on export)
- Stacked markers when multiple waypoints share a location, rendered
  with a small vertical offset so they're all visible and clickable
- **Add by km**: enter a distance from the race brief instead of
  hunting for the spot on the map (drawer menu → Add by km, or the
  "Add by km" button on the empty waypoints state)
- **Cutoff times**: optional per-waypoint cutoff (e.g. `12:30` or
  `4:15:00`) shown in the waypoint list and splits table, round-tripped
  through GPX `<extensions>` so other tools just ignore them
- **Auto-create from climbs**: one-click summit waypoints at the top of
  every detected hill (drawer menu → Auto-create from climbs)
- GPX `<sym>` / `<type>` symbols preserved so Garmin Connect maps them
  to the right course-point icons on your watch

### Elevation analysis
- Interactive elevation profile with hover crosshair synchronised to
  the map
- Waypoint icons drawn on the profile so you can see aid stations,
  summits and checkpoints in elevation context at a glance
- Total ascent / descent computed with hysteresis filtering (no more
  GPS jitter inflating your elevation gain by 30%)
- **Climbs tab**: automatic detection of every significant hill on the
  track, with length, gain, average grade, max grade (over a 100 m
  sliding window) and a difficulty badge. Hovering a climb highlights
  its extent on the map and on the elevation chart
- **Descents tab**: symmetric counterpart to climbs — every significant
  downhill is detected with length, loss, average grade, max grade and
  a difficulty badge. In trail-running mode the badge estimates **knee
  impact** (eccentric quad load), tuned slightly tighter than the climb
  ladder because long descents are often the limiting factor in
  ultras. Hovering a descent paints it orange on the map and on the
  elevation chart
- **Activity profile** (Trail run / Bike): drives climb / descent
  category thresholds and grade-color ramps. Trail-running mode treats
  a 10% pitch as moderate; bike mode keeps the FIETS-based Cat 4 → HC
  scale and tighter grade colors. The choice is persisted in
  localStorage
- **Splits tab**: race-brief style table of waypoints with cumulative
  distance from start, leg distance to the next point and the cutoff
  time when set
- **Profile detail view**: tap the expand icon on the small chart to
  open a full-screen detail with a tall interactive profile, hover
  read-out of distance + elevation, and Climbs / Descents / Splits /
  Waypoints tabs side by side — for inspecting each section of the
  route without the map competing for attention

### Trace de Trail import
- Auto-detected on import: if the GPX metadata links back to a
  [tracedetrail.fr](https://tracedetrail.fr) race page, you're offered
  a one-click waypoint pull right after opening the file
- Or paste a race URL manually via **Tools → Import waypoints from
  Trace de Trail**
- Pulls every waypoint the downloadable GPX strips out: aid stations,
  medical points, time checkpoints, summits, …
- Handles secondary and tertiary markers (`type2` / `type3`) so an
  "aid station + medical" location imports as two distinct waypoints
- Place names from `infobulleTitre` are preserved
- Routes through CORS proxies with automatic fallback

### Map
- Multiple tile layers (OpenStreetMap, OpenTopoMap, satellite,
  Mapy.com outdoor, and more)
- Hover-aware track highlighting with screen-space caching so 50 km+
  tracks stay smooth
- **Route color picker**: 10-swatch palette (Strava red default) so
  the track stays readable on top of busy basemaps (e.g. the magenta
  tourist-trail dashes on the Mapy.com outdoor layer). Choice is
  persisted in localStorage

## Running locally

Requirements: [Flutter](https://docs.flutter.dev/get-started/install)
3.11 or newer.

```bash
flutter pub get
cp env.example.json env.json   # fill in your keys (see below)
flutter run -d chrome --dart-define-from-file=env.json
```

`env.json` is gitignored. The VS Code launch configs already pass
`--dart-define-from-file=env.json` so pressing F5 works once the file
exists.

### Configuration keys

| Key            | Used for                             | Required? |
| -------------- | ------------------------------------ | --------- |
| `MAPY_API_KEY` | Mapy.com outdoor / satellite tiles   | Optional — if unset, the Mapy layer is hidden and OpenStreetMap is the default |

Grab a free key at <https://developer.mapy.com>. Mapy.com keys should
be **domain-restricted** in the Mapy dashboard — anything shipped in a
web bundle is visible to the browser.

## Building for the web

```bash
flutter build web --release --dart-define-from-file=env.json
```

The production bundle lands in `build/web/`. Deploy the contents to
any static host of your choice (Netlify, Vercel, GitHub Pages,
Cloudflare Pages, Azure Static Web Apps, Firebase Hosting, …). This
repo intentionally ships no provider-specific deployment config — wire
up your own pipeline and pass `MAPY_API_KEY` through as a CI secret.

For Flutter web's CanvasKit renderer you generally want to serve the
build with these response headers, regardless of host:

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: credentialless
Cache-Control: public, max-age=31536000, immutable   # for *.js, *.wasm, assets
```

In CI, either pass the key inline:

```yaml
- run: flutter build web --release --dart-define=MAPY_API_KEY=${{ secrets.MAPY_API_KEY }}
```

or materialise `env.json` from a secret first:

```yaml
- run: jq -n --arg k "$MAPY_API_KEY" '{MAPY_API_KEY:$k}' > env.json
  env:
    MAPY_API_KEY: ${{ secrets.MAPY_API_KEY }}
- run: flutter build web --release --dart-define-from-file=env.json
```

## Project layout

```
lib/
  main.dart                      app entry point
  models/gpx_models.dart         GPX data model + waypoint types
  providers/gpx_provider.dart    state management (ChangeNotifier)
  screens/editor_screen.dart     top-level editor layout
  services/
    gpx_parser.dart              GPX XML parse / export
    tracedetrail_importer.dart   race-page waypoint scraper
  utils/
    elevation_profile.dart       distance / elevation / snap math
    climb_detector.dart          hill detection with grade analysis
    descent_detector.dart        downhill detection + knee-impact scoring
    geo_utils.dart               distance + hysteresis gain / loss
    waypoint_icons.dart          type → icon / color
  widgets/
    toolbar.dart                 file + edit actions
    sidebar.dart                 stats + points / waypoints / climbs / descents / splits tabs
    map_view.dart                flutter_map rendering + hover
    elevation_profile_chart.dart interactive profile
    welcome_dialog.dart          first-run intro + Ko-fi link
web/
  index.html                     SEO meta, OG cards, JSON-LD, crawlable copy
  manifest.json                  PWA manifest
  robots.txt, sitemap.xml        crawler hints
```

## Contributing

Issues and pull requests are welcome. A few conventions:

- Run `dart analyze` and `dart format .` before pushing — CI will
  reject formatting drift.
- Keep commits scoped and descriptive; conventional-commit style is a
  plus but not required.
- No new runtime dependencies without a matching `Why:` in the PR
  description — the project aims to stay lean.

## Acknowledgements

- [`flutter_map`](https://pub.dev/packages/flutter_map) for the map
  widget, and OpenStreetMap, OpenTopoMap and Mapy.com for tiles.
- [Trace de Trail](https://tracedetrail.fr) for publishing race
  waypoint data that the importer draws from.

## License

MIT — see [LICENSE](LICENSE).
