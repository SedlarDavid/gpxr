# Changelog

All notable changes to GPXR are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.6.0] — 2026-05-16

### Added
- **Export TCX (Garmin)**: drawer menu → Export TCX writes a Garmin
  Training Center Database v2 `<Course>` document with each waypoint
  emitted as an ordered `<CoursePoint>` block. Garmin Connect places
  course points by `<Time>` rather than projecting lat/lon onto the
  nearest segment, so on out-and-back / lollipop routes every aid
  station now lands at the correct km when the course is uploaded to a
  Garmin watch. Times are synthesized from a constant trail-running
  pace (≈ 8 km/h) — Garmin only requires monotonic ordering, not
  realistic timing. The plain `.gpx` export is unchanged for tools
  like mapy.com that don't speak TCX.

## [1.5.1] — 2026-05-16

### Fixed
- **Waypoint km on out-and-back / lollipop routes**: waypoints added
  by km (or auto-generated, snapped, or scraped) now persist their
  along-track distance instead of being re-projected from lat/lon on
  every render. On routes that pass the same point twice (an
  out-and-back course's aid station, a lollipop's neck), projection
  would pick whichever pass was geometrically closest — often the
  wrong one. The stored distance round-trips through GPX as
  `<extensions><gpxr:trackDistance>` and is invalidated whenever the
  waypoint is moved to a free lat/lon.

## [1.5.0] — 2026-05-01

### Added
- **Edit waypoint by km**: the edit dialog now exposes the waypoint's
  projected distance along the track. Type a new value to slide the
  waypoint along the route — handy when a race brief moves an aid
  station by a few hundred metres after the GPX was already annotated.
- Single-track GPX files that put their name only in `<metadata>` now
  mirror that name onto the track itself, so the sidebar and re-export
  carry the route name instead of "Track 1".

### Fixed
- GPX exports always end in `.gpx`, even when the source file was
  imported as `*.xml`. Avoids round-tripping `route.xml → route.xml`,
  which left users wondering why the download wasn't a real GPX.
- Dark-mode contrast on the type-chip row in the Edit Waypoint dialog
  — the unselected chips' labels were inheriting Material's default
  dim colour and looked unreadable on the dark surface.
- Dark-mode contrast on the elevation-profile detail view's app bar —
  the title used to render as light-on-light because the bar was
  hard-coded to `Colors.white`.

## [1.4.0] — 2026-04-22

### Added
- **Tracks tab**: per-track row with distance, gain/loss, point count,
  visibility toggle, color picker, rename and delete. Hidden tracks
  drop out of the global stats, climbs, descents and elevation
  profile, so the aggregated picture only reflects what's visible.
- **Multi-file merge**: append additional GPX files into the current
  session without losing what's already loaded. Each merged track
  gets its own colour from the palette so they're easy to tell apart.
- **Dark mode**: slate-tinted dark palette (default) plus a sun/moon
  toggle in the toolbar. Persisted in localStorage.

### Performance
- Cached profile / climbs / descents / waypoint projections — the
  combined profile across visible tracks is built once per mutation
  and reused, so hover and tab-switch on a 45 k-point track stay at
  60 fps. Cosmetic state (selection, edit mode) doesn't invalidate
  the cache.

## [1.3.0] — 2026-04-12

### Added
- **Descents tab**: symmetric counterpart to climbs — every
  significant downhill is detected with length, loss, average grade,
  max grade and a difficulty badge. In trail-running mode the badge
  estimates **knee impact** (eccentric quad load), tuned slightly
  tighter than the climb ladder because long descents are often the
  limiting factor in ultras. Hovering a descent paints it orange on
  the map and on the elevation chart.

## [1.2.0] — 2026-04-05

### Added
- **Profile detail view**: tap the expand icon on the small chart to
  open a full-screen detail with a tall interactive profile, hover
  read-out of distance + elevation, and Climbs / Descents / Splits /
  Waypoints tabs side by side — for inspecting each section of the
  route without the map competing for attention.

## [1.1.0] — 2026-03-20

### Added
- **Add by km**: enter a distance from the race brief instead of
  hunting for the spot on the map (drawer menu → Add by km, or the
  "Add by km" button on the empty waypoints state).
- **Route colour picker**: 10-swatch palette (Strava red default) so
  the track stays readable on busy basemaps. Persisted in
  localStorage.
- Responsive layout polish for phones — draggable bottom panel
  instead of side-by-side editor.
- "Request feature" link in the toolbar drawer that opens a pre-filled
  GitHub issue.

## [1.0.0] — 2026-02-28

Initial public release.

### Highlights
- GPX import / export, multi-tile basemap, point edit / move / insert
  / reverse.
- Rich waypoint types (aid station, medical, water, food, summit,
  camp, parking, info, danger, start, finish, generic) with snap-to-
  track on click or drop. Garmin course-point compatible on export.
- Cutoff times round-tripped through GPX `<extensions>` so other
  tools just ignore them.
- Auto-create summit waypoints from detected climbs.
- Trace de Trail importer: paste a race URL or auto-detect it from
  imported GPX metadata to pull every waypoint the downloadable GPX
  strips out (aid stations, medical points, time checkpoints, …).
- Interactive elevation profile with hover crosshair synchronised to
  the map, hysteresis-filtered ascent / descent, climb detection with
  difficulty badges, splits table.
- Activity profile (Trail run / Bike) drives climb / descent
  thresholds and grade-colour ramps.

[1.6.0]: https://github.com/SedlarDavid/gpxr/compare/v1.5.1...v1.6.0
[1.5.1]: https://github.com/SedlarDavid/gpxr/compare/v1.5.0...v1.5.1
[1.5.0]: https://github.com/SedlarDavid/gpxr/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/SedlarDavid/gpxr/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/SedlarDavid/gpxr/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/SedlarDavid/gpxr/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/SedlarDavid/gpxr/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/SedlarDavid/gpxr/releases/tag/v1.0.0
