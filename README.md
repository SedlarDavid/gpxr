# gpxr

A lightweight GPX route editor for the web, built with Flutter. Designed
for trail runners and hikers who want to plan, tweak, and annotate GPX
tracks from their browser without installing anything.

## Features

### Route editing
- Import and export GPX files
- Add, move, delete, and reorder track points directly on the map
- Reverse route direction in one click
- Smart insert: click near the track and the new point is placed on
  the closest segment instead of at the end

### Waypoints
- Rich set of built-in types: aid station, medical, water, food, summit,
  camp, parking, info, danger, start, finish, generic
- Snap-to-track on click or drop so waypoints line up exactly with the
  course (Garmin course-point compatible on export)
- Stacked markers when multiple waypoints share a location, rendered
  with a small vertical offset so they're all visible and clickable
- GPX `<sym>` / `<type>` symbols preserved so Garmin Connect maps them
  to the right course-point icons on your watch

### Elevation analysis
- Interactive elevation profile with hover crosshair synchronized to
  the map
- Total ascent / descent computed with hysteresis filtering (no more
  GPS jitter inflating your elevation gain by 30%)
- **Climbs tab**: automatic detection of every significant hill on the
  track, with length, gain, average grade, max grade (over a 100 m
  sliding window), and a cycling-style category badge (Cat 4 → HC).
  Grade percentages are color-coded

### Trace de Trail import
- Auto-detected on import: if the GPX metadata links back to a
  [tracedetrail.fr](https://tracedetrail.fr) race page, you're offered
  a one-click waypoint pull right after opening the file
- Or paste a race URL manually to enrich any track
- Pulls every waypoint the downloadable GPX strips out: aid stations,
  medical points, time checkpoints, summits, …
- Handles secondary and tertiary markers (`type2` / `type3`) so an
  "aid station + medical" location imports as two distinct waypoints
- Place names from `infobulleTitre` are preserved
- Routes through CORS proxies with automatic fallback

### Map
- Multiple tile layers (OpenStreetMap, OpenTopoMap, satellite, Mapy.cz,
  and more)
- Hover-aware track highlighting with screen-space caching so 50 km+
  tracks stay smooth

## Running locally

Requirements: [Flutter](https://docs.flutter.dev/get-started/install)
3.11 or newer.

```bash
flutter pub get
cp env.example.json env.json   # fill in your keys
flutter run -d chrome --dart-define-from-file=env.json
```

`env.json` is gitignored. VS Code launch configs already pass the file,
so hitting F5 just works once the file exists.

### Configuration keys

| Key             | Used for                              | Required? |
| --------------- | ------------------------------------- | --------- |
| `MAPY_API_KEY`  | Mapy.com outdoor / satellite tiles    | Optional — if unset, the Mapy layer is hidden and OSM is the default |

Mapy.com keys should be **domain-restricted** in the Mapy dashboard —
anything in a web bundle is visible to the browser.

## Building for the web

```bash
flutter build web --release --dart-define-from-file=env.json
```

The production bundle lands in `build/web/`. Deploy it to any static
host — Firebase Hosting config is already included (`firebase.json`),
just set your project id in `.firebaserc` and run `firebase deploy`.

### Deploy-time secrets

- **GitHub Actions → Firebase** (`.github/workflows/firebase-deploy.yml`):
  store `MAPY_API_KEY` as a repo secret. The workflow writes it into
  `env.json` before the build step.
- **Azure Static Web Apps**: the auto-generated SWA workflow (usually
  committed to the repo the first time you connect Azure) needs the
  same `env.json` step before its `flutter build web` invocation, or
  an equivalent `--dart-define=MAPY_API_KEY=${{ secrets.MAPY_API_KEY }}`
  flag.

## Project layout

```
lib/
  main.dart                  app entry point
  models/gpx_models.dart     GPX data model + waypoint types
  providers/gpx_provider.dart state management (ChangeNotifier)
  screens/editor_screen.dart  top-level editor layout
  services/
    gpx_parser.dart          GPX XML parse / export
    tracedetrail_importer.dart  race-page waypoint scraper
  utils/
    elevation_profile.dart   distance / elevation / snap math
    climb_detector.dart      hill detection with grade analysis
    geo_utils.dart           distance + hysteresis gain / loss
    waypoint_icons.dart      type → icon / color
  widgets/
    toolbar.dart             file + edit actions
    sidebar.dart             stats + points / waypoints / climbs tabs
    map_view.dart            flutter_map rendering + hover
    elevation_profile_chart.dart  interactive profile
```

## License

MIT
