<!--
SPDX-FileCopyrightText: Copyright © 2026 technosf <https://github.com/technosf>

SPDX-License-Identifier: GPL-3.0-or-later
-->
# Tuner Code Quality

How Tuner's source is measured, what the numbers mean, the current scores, and where the
biggest maintainability and performance opportunities are.

* Measured: 2026-11-06, commit `90981c1` plus the uncommitted working tree
* Baseline: the 2.2.0-beta.2 release metadata commit `5b150ef` (2026-07-10). There is no git tag
  for it, so the commit is used
* Tool: [`scripts/code_metrics.py`](../scripts/code_metrics.py) (Python 3, standard library only)

## 1. Purpose and how to use this

Run the measurements before a release, and on any change that touches a hotspot listed in section 4.
Paste the new scores into section 4 and note the date and commit. A score that moves the wrong way
needs a reason in the pull request.

```
# Tuner's own code, against a release checkout
git archive <release-commit> src | tar -x -C /tmp/rel
python3 scripts/code_metrics.py --root src --compare /tmp/rel/src --top 12

# Vendored code on its own
python3 scripts/code_metrics.py --root src/Widgets/granite

# Machine-readable summary
python3 scripts/code_metrics.py --root src --json metrics.json
```

The script always leaves out `Widgets/granite` (vendored) and `Services/ScreenshotMode` (a debug-only
tool for taking store screenshots, compiled only in `DEBUG_LOCAL` builds). `--exclude <text>` adds more.

## 2. Scope

| In scope | Out of scope |
|---|---|
| `src/**/*.vala` (63 files) | `po/` translations, `data/` resources, packaging files, `Services/ScreenshotMode.vala` (debug-only) |
| Reported separately: `src/Widgets/granite/` (vendored UI widgets, about 2,000 SLOC) | Third-party libraries |

Vendored code is excluded from the headline scores because Tuner does not own its design. It is
measured on its own in section 4.4 so that it does not hide, or inflate, Tuner's results.

**Not measured by the script** (measure these by hand, see section 3.3): compiler warnings, test coverage
(the repository has no tests), runtime performance, memory use.

## 3. What is measured

### 3.1 Metrics, definitions and thresholds

The script reads each Vala file, blanks out comments and strings, and scans braces and keywords to
find functions. It is a heuristic, not a compiler. Use it for hotspots and trends. Numbers are only
comparable between runs of the same script version.

| Metric | Definition | Good | Watch | Act |
|---|---|---|---|---|
| **Cyclomatic complexity (CC)**, per function | 1 + count of `if`, `for`, `foreach`, `while`, `case`, `catch`, `&&`, `\|\|`, `??`, and `? :` in the function body (lambdas count toward the enclosing function) | 1-10 | 11-20 | over 20 |
| CC distribution | Average, median, 90th percentile, maximum, and counts over 10 and over 20 | p90 at most 10 | any function over 10 | any function over 20 |
| **Function length** | Non-blank, non-comment lines from the signature to the closing brace | up to 50 | 51-100 | over 100 |
| **Parameters** | Top-level parameters per function | up to 4 | 5 | over 5 |
| **Nesting depth** | Deepest nested `{}` block inside a function | up to 3 | 4 | over 4 |
| **File size** | SLOC (source lines without blanks and comments) | up to 300 | 301-500 | over 500 |
| **Comment density** | Comment lines / (SLOC + comment lines) | 10-35 % | below 10 % | n/a, a very high value usually means commented-out code or vendored headers |
| **Public API documented** | Share of public/internal/protected members and public types preceded by a `/** */` comment | 85 % or more | 60-84 % | below 60 % |
| **Duplication** | Share of significant lines that sit inside a run of 6 identical normalized lines occurring more than once (windows that repeat the same lines, such as data tables, are ignored) | under 3 % | 3-8 % | over 8 % |
| **Maintainability index (MI)** | `max(0, (171 - 5.2 ln(V) - 0.23 G - 16.2 ln(LOC)) * 100 / 171)` per file, where V is a token-based Halstead volume, G the sum of function CC, LOC the SLOC. Reported SLOC-weighted | 20-100 | 10-19 | 0-9 |
| **Tech-debt markers** | `TODO`, `FIXME`, `HACK`, `XXX`, `@todo` in comments | trending down | | stale ones with no owner |
| **Commented-out code** | `//` lines that look like statements | 0 | | any, git keeps the history |
| **Empty catch blocks** | `catch (...) { }` with no body | 0 | | any |

The CC bands follow McCabe and the SEI risk categories (1-10 simple, 11-20 moderate, 21-50 high,
over 50 untestable). The MI bands follow the Visual Studio convention. The MI is harsh for files of
several hundred lines, so use it to rank files and watch the trend, not as an absolute grade.

Known false positives: a flat `switch` that maps values to strings scores a high CC without being hard
to read, and the country and language lookup tables score as very long functions while being data,
not logic.

### 3.2 Anti-pattern scan (robustness and performance)

Counts of patterns that deserve a look. A count is a prompt to inspect, not a verdict.

| Check | Pattern | Why it matters |
|---|---|---|
| Blocking HTTP | `HttpClient.GET(` / `HEAD(` | Runs on the caller's thread. On the UI thread it freezes the window until the response or the 3 s timeout |
| Eager debug strings | `debug(@"...")` | Vala builds the string before `debug()` checks whether logging is on |
| Timers | `Timeout.add*`, `Idle.add*` | Each needs a matching removal, or it keeps running and holds objects alive |
| Signal connect : disconnect | `.connect(` vs `.disconnect(` | A large gap on long-lived objects can mean handlers that outlive their widgets |
| Empty catch | `catch (...) { }` | Errors disappear silently |
| Global `app()` calls | `app()` | Hidden dependency on the global application object, which makes code hard to test |
| `to_array()` | collection copies | Allocation in loops and hot paths |
| Sleeps | `Thread.sleep` / `usleep` | Blocks a thread |

### 3.3 Measured by hand

| Measure | How |
|---|---|
| Compiler warnings | `meson compile -C build/meson 2>&1 \| grep -c warning`. The target is 0 new warnings |
| Test coverage | There are no tests (`meson.build` has no `test()` and there is no `tests/` folder). Add them, then measure with `gcov` or `lcov` |
| Runtime hot spots | `perf record` or GNOME Sysprof while switching stations, searching and running Jukebox for a few minutes |
| Memory growth | Open and close the search view and the history popover 50 times with `valgrind --tool=massif` or Sysprof and look for steady growth |
| Network stalls | Run with `G_MESSAGES_DEBUG=all`. `HttpClient` logs elapsed milliseconds for every failed request |

## 4. Current scores

Measured 2026-11-06 on commit `90981c1` plus the uncommitted working tree (async start-up and connection handling, `ConnectionCoordinator`, `ServerSelector`, `NetworkState`, the `HttpClient` retry rewrite and a round of complexity reductions). Baseline: `5b150ef` (2.2.0-beta.2), re-measured with the current script. Tuner-authored code only; vendored code is in 4.6.

### 4.1 Summary: working tree against the 2.2.0-beta.2 release

| Metric | Current | Baseline | Change |
|---|---|---|---|
| Files | 63 | 53 | +10 |
| Source lines (SLOC) | 11443 | 8954 | +2489 |
| Comment lines | 6283 | 4190 | +2093 |
| Comment density % | 35.4 | 31.9 | +3.5 |
| Functions / methods | 676 | 496 | +180 |
| Average CC | 2.87 | 2.83 | +0.04 |
| Median CC | 2 | 2 | +0 |
| 90th percentile CC | 6 | 6 | +0 |
| Max CC | 13 | 24 | -11 |
| Functions CC > 10 | 9 | 10 | -1 |
| Functions CC > 20 | 0 | 1 | -1 |
| Functions > 50 SLOC | 19 | 17 | +2 |
| Functions > 100 SLOC | 4 | 5 | -1 |
| Functions > 5 params | 3 | 3 | +0 |
| Functions nesting > 4 | 0 | 2 | -2 |
| Files > 500 SLOC | 4 | 0 | +4 |
| Files > 1000 SLOC | 0 | 0 | +0 |
| Public API documented % | 99.8 | 72.5 | +27.3 |
| Duplicated lines % | 2.3 | 3.1 | -0.8 |
| Maintainability index (SLOC-weighted) | 13.4 | 15.1 | -1.7 |
| Files with MI < 20 | 24 | 20 | +4 |
| TODO/FIXME/HACK markers | 10 | 12 | -2 |
| Commented-out code lines | 49 | 68 | -19 |
| Empty catch blocks | 3 | 5 | -2 |
| Blocking HTTP call sites | 0 | 7 | -7 |
| Eager debug(@"...") calls | 0 | 33 | -33 |
| Timer / idle registrations | 38 | 33 | +5 |
| Signal connect : disconnect | 153 : 13 | 111 : 11 |  |
| Global app() calls | 35 | 60 | -25 |

### 4.2 Complexity hotspots

Highest cyclomatic complexity:

| Location | Function | CC | SLOC | Params | Max nesting |
|---|---|---|---|---|---|
| `Models/Station.vala:475` | set_up_to_date_with | 13 | 27 | 1 | 1 |
| `Providers/RadioBrowser.vala:628` | read_stats | 12 | 39 | 1 | 2 |
| `Providers/RadioBrowser.vala:681` | station_query_async | 12 | 46 | 3 | 3 |
| `Ext/GstFader.vala:389` | begin_fade | 12 | 56 | 0 | 3 |
| `Providers/RadioBrowser.vala:868` | get_srv_api_servers_async | 11 | 35 | 0 | 3 |
| `Providers/ServerSelector.vala:198` | first_to_answer | 11 | 29 | 1 | 3 |
| `Services/DBusMediaPlayer.vala:234` | MediaPlayerPlayer | 11 | 75 | 3 | 2 |
| `Models/StreamMetadata.vala:227` | get_image_url | 11 | 24 | 0 | 2 |
| `Controllers/PlayerController.vala:77` | set_play_state | 11 | 50 | 1 | 3 |
| `Services/StarStore.vala:535` | check_station_currency | 10 | 36 | 0 | 3 |
| `Ext/GstFader.vala:357` | start_crossfade | 10 | 30 | 0 | 3 |
| `Models/StreamMetadata.vala:171` | update_from_metadata_values | 10 | 39 | 0 | 2 |

Longest functions (the two `get` entries are data tables, not logic):

| Location | Function | SLOC | CC |
|---|---|---|---|
| `Models/Countries.vala:26` | get | 256 | 2 |
| `Models/Languages.vala:46` | get | 193 | 2 |
| `Widgets/PreferencesPopover.vala:23` | construct | 143 | 4 |
| `Widgets/Display.vala:168` | Display | 107 | 7 |
| `Widgets/HeaderBar.vala:129` | HeaderBar | 96 | 7 |
| `Widgets/ShareStreamWindow.vala:57` | ShareStreamWindow | 95 | 7 |
| `Widgets/HistoryButton.vala:145` | build_popover | 85 | 1 |
| `Services/DBusMediaPlayer.vala:234` | MediaPlayerPlayer | 75 | 11 |
| `Widgets/PlayingStationInfo.vala:79` | PlayingStationInfo | 72 | 5 |
| `Widgets/HistoryButton.vala:717` | rebuild_history_row | 70 | 6 |
| `Widgets/StationNoteWindow.vala:38` | StationNoteWindow | 68 | 3 |
| `Widgets/TitleBox.vala:59` | TitleBox | 64 | 4 |

### 4.3 Files

Largest files:

| File | SLOC | Functions | Avg CC | MI |
|---|---|---|---|---|
| `Widgets/HistoryButton.vala` | 602 | 33 | 2.7 | 0.0 |
| `Widgets/Display.vala` | 583 | 24 | 2.9 | 0.0 |
| `Providers/RadioBrowser.vala` | 517 | 32 | 4.1 | 0.0 |
| `Services/DBusMediaPlayer.vala` | 513 | 28 | 3.2 | 0.0 |
| `Ext/GstFader.vala` | 483 | 35 | 3.0 | 0.0 |
| `Services/StarStore.vala` | 444 | 31 | 3.4 | 0.0 |
| `Application.vala` | 404 | 36 | 2.1 | 3.2 |
| `Widgets/Window.vala` | 387 | 27 | 1.6 | 7.8 |
| `Widgets/base/AnimatedIcons.vala` | 345 | 18 | 2.8 | 7.9 |
| `Widgets/PlayingStationInfo.vala` | 328 | 16 | 3.1 | 9.5 |
| `Widgets/ShareStreamWindow.vala` | 298 | 15 | 2.7 | 10.6 |
| `Ext/GstStreamPlayer.vala` | 288 | 20 | 3.5 | 8.2 |

Lowest maintainability index:

| File | MI | SLOC | Total CC |
|---|---|---|---|
| `Providers/RadioBrowser.vala` | 0.0 | 517 | 130 |
| `Services/DBusMediaPlayer.vala` | 0.0 | 513 | 91 |
| `Services/StarStore.vala` | 0.0 | 444 | 104 |
| `Ext/GstFader.vala` | 0.0 | 483 | 106 |
| `Widgets/Display.vala` | 0.0 | 583 | 70 |
| `Widgets/HistoryButton.vala` | 0.0 | 602 | 90 |
| `Application.vala` | 3.2 | 404 | 74 |
| `Widgets/Window.vala` | 7.8 | 387 | 43 |
| `Widgets/base/AnimatedIcons.vala` | 7.9 | 345 | 50 |
| `Ext/GstStreamPlayer.vala` | 8.2 | 288 | 69 |
| `Models/History.vala` | 9.4 | 276 | 72 |
| `Widgets/PlayingStationInfo.vala` | 9.5 | 328 | 49 |

### 4.4 Duplication and technical debt

Duplication between and within files (6-line windows):

| File A | File B | Shared windows |
|---|---|---|
| `Widgets/base/AnimatedIcons.vala` | `Widgets/base/AnimatedIcons.vala` | 15 |
| `Widgets/HistoryButton.vala` | `Widgets/HistoryButton.vala` | 6 |
| `Ext/GstFader.vala` | `Ext/GstFader.vala` | 2 |
| `Models/StationListBoxConfig.vala` | `Widgets/base/StationListBox.vala` | 2 |
| `Widgets/ShareStreamWindow.vala` | `Widgets/StationNoteWindow.vala` | 2 |
| `Models/HeartedArchive.vala` | `Widgets/HistoryButton.vala` | 1 |
| `Controllers/DirectoryController.vala` | `Controllers/DirectoryController.vala` | 1 |

Debt markers:

| Location | Marker |
|---|---|
| `Models/Station.vala:482` | //  && (this.changeuuid == p.changeuuid) // TODO Radio browser changeuuids broken |
| `Models/StreamPlayer.vala:94` | // FIXME |
| `Controllers/DirectoryController.vala:111` | * @brief Get a collection of Station station by its stream URL. // TODO Not working at Pro |
| `Controllers/DirectoryController.vala:115` | * @todo radio-browser should handle URL queries, but is broken |
| `Controllers/DirectoryController.vala:443` | // TODO Place filter here? |
| `Widgets/Display.vala:517` | // true // TODO Implement filter |
| `Widgets/Display.vala:980` | // true // TODO Implement filter |
| `Widgets/Window.vala:147` | //this.resize(900, 600);  // FIXME Comment out |
| `Widgets/base/StationList.vala:89` | // FIXME Wraps stations in StationButtons, adds to flowbox |
| `Widgets/base/StationListBoxContent.vala:11` | // FIXME Refactor content out to a model - can it be shard with search? |

Commented-out code by file: `Services/DBusMediaPlayer.vala` 8, `Widgets/Display.vala` 8, `Models/Station.vala` 6, `Controllers/DirectoryController.vala` 5, `Ext/GstStreamPlayer.vala` 4, `Widgets/base/CyclingRevealLabel.vala` 4, `Widgets/base/StationListBoxContent.vala` 3, `Widgets/HeaderBar.vala` 2

### 4.5 Anti-pattern scan

| Check | Meaning | Count | Top files |
|---|---|---|---|
| sync_http_get | Blocking HTTP on the calling (usually UI) thread | 0 |  |
| eager_debug | debug(@"...") builds its string even when debug logging is off | 0 |  |
| timers | Timers / idle callbacks (check each is removed) | 38 | `Ext/GstFader.vala` 6, `Widgets/PlayingStationInfo.vala` 6, `Application.vala` 3, `Services/DBusMediaPlayer.vala` 3 |
| connects | Signal connections | 153 | `Widgets/HistoryButton.vala` 21, `Widgets/Display.vala` 19, `Widgets/HeaderBar.vala` 11, `Services/DBusMediaPlayer.vala` 10 |
| disconnects | Signal disconnections | 13 | `Controllers/PlayerController.vala` 3, `Coordinators/PlaybackRecoveryCoordinator.vala` 2, `Coordinators/UsageTrackingCoordinator.vala` 2, `Widgets/StationButton.vala` 2 |
| empty_catch | Empty catch blocks (swallowed errors) | 3 | `Application.vala` 2, `Services/StarStore.vala` 1 |
| app_global | Global app() accessor calls (hidden coupling) | 35 | `Widgets/PreferencesPopover.vala` 9, `Widgets/StationContextMenu.vala` 5, `Widgets/Window.vala` 5, `Widgets/StationNoteWindow.vala` 4 |
| to_array | Collection copies via to_array() | 4 | `Providers/RadioBrowser.vala` 2, `Controllers/DirectoryController.vala` 1, `Controllers/JukeboxController.vala` 1 |
| sleep | Thread sleeps | 0 |  |

Blocking HTTP call sites: none.

### 4.6 Vendored code (`src/Widgets/granite`)

4 files, 2038 SLOC, 167 functions, highest CC 21. Not owned by Tuner, so it is kept out of the scores above. Upstream fixes should be taken from the Granite project instead of edited in place.


### 4.7 What the scores say

* **Function-level complexity is healthy and better than at release.** Median CC is 2 and the 90th
  percentile is 6. The maximum CC is 13 (24 at release, 29 on 2026-10-21) and no function is over 20.
  Nine of 676 functions exceed 10. The old worst case, `GstStreamPlayer.bus_callback`, is now a plain
  dispatch to per-message handlers.
* **The robustness and performance counts are all down.** Blocking HTTP call sites went from 7 to 0
  and eager `debug(@"...")` calls from 33 to 0. `app()` calls fell from 60 to 35, because the
  network state, events, settings and provider are now passed to the classes that use them. Duplication
  fell from 3.1 % to 2.3 %, commented-out code from 68 to 49 lines, empty catch blocks from 5 to 3 and
  debt markers from 12 to 10. Public API documentation is 99.8 % (72.5 % at release).
* **File-level maintainability is the weak spot, and it got worse.** Four files are now over 500 SLOC
  (none at release): `HistoryButton` 602, `Display` 583, `RadioBrowser` 517 and `DBusMediaPlayer` 513.
  The SLOC-weighted maintainability index fell from 15.1 to 13.4 and files under 20 went from 20 to 24.
  The code base grew by 2,489 SLOC (28 %) and 10 files since the release, and the growth went into
  existing large files as well as new ones.
* **Splitting functions moved complexity around more than it removed it.** The function count rose from
  496 to 676 while the average CC stayed level (2.83 to 2.87). `RadioBrowser` still has the highest total
  CC (130), now with the server choice in `ServerSelector`.
* **New hotspots to watch:** `ServerSelector.first_to_answer` (CC 11, the parallel probe race) and
  `PlayerController.set_play_state` (CC 11).
* **Timers rose from 33 to 38** (the connection retry, fades and the jingle timer). Each is removed or
  one-shot, but the count is worth watching.
* **No tests exist**, so none of the figures above are backed by an automated safety net. The changes in
  this round were built and run by hand only.

## 5. Opportunities

Ordered by value for the effort. "Effort": S is under half a day, M is one or two days, L is a week or more.
The last column is the metric in section 4 that should move.

### 5.1 Maintainability

| # | Finding and evidence | Action | Effort | Metric to watch |
|---|---|---|---|---|
| M1 | **No automated tests.** There is no `test()` in `meson.build` and no `tests/` folder | Add a `tests/` folder with GLib tests (`GLib.Test`) and a meson `test()` target. First candidates, all pure logic: `StationSession`, `RadioBrowser.get_search_query_params`, `Station.make` JSON parsing, `StationSet` paging, `DataProvider.SortOrder.to_string` | M | Tests run in CI; coverage reported |
| M2 | *Done 2026-11-06: error, tag and level handling are separate handlers; the maximum CC is 13.* **`GstStreamPlayer.bus_callback`**: CC 29, 97 SLOC, nesting 7 (`Ext/GstStreamPlayer.vala:200`) | Split the big `switch` into one handler per message type (`on_error`, `on_state_changed`, `on_tag`, ...) and move the error-logging block into a helper such as `describe_gst_error()` | S | Max CC under 15; nesting under 4 |
| M3 | *Partly done 2026-11-06: the sync query is gone, there is one retry policy (`HttpClient`), and server choice moved to `ServerSelector`. The file is still 517 SLOC, MI 0.0.* **`RadioBrowser.vala`** is 473 SLOC with MI 0.0 and total CC 106. It does server discovery, failover, query building, HTTP and JSON parsing. `station_query` and `station_query_async` are near copies (CC 10 each) | Split into server discovery and failover, query building, and response parsing. Make the sync query a wrapper around the async one, or retire the sync one once callers are async (see P1). That also removes the duplication inside the file | M-L | MI above 20; one copy of the retry logic |
| M4 | *Partly done 2026-11-06: `initialize` is split into builders; the file is still 583 SLOC.* **`Display.vala`**: 478 SLOC, MI 4.8, `initialize` 165 SLOC (CC 13), constructor 102 SLOC, 19 signal connections. A `FIXME` in `StationListBoxContent.vala` already asks for the content to move out to a model | Break `initialize` into builders (sidebar categories, search, saved searches). Keep moving behaviour out of the widget into controllers, as was done for Jukebox | M | Longest-function list; MI |
| M5 | **`GstFader.vala`** is 483 SLOC, MI 0.0, six timers, and is created by `GstStreamPlayer` as a shared fader (`GstStreamPlayer.vala:400`). The crossfade API in `GstStreamPlayer` is commented out | Check whether crossfade is still used by the UI. If only fade in/out remains, trim the class to that. Otherwise split the curves, timing and playbin handling | M | SLOC; MI; timer count |
| M6 | *Partly done 2026-11-06: `SortOrder.to_string` now reads the enum nick; the country and language tables are still code.* **Data in code**: `Countries.get` is 256 SLOC and `Languages.get` is 193 SLOC. `SortOrder.to_string` is a CC-18 switch | Move the country and language tables to a resource file (JSON or CSV in the GResource bundle). Replace `to_string` with a lookup | S-M | Longest-function list; CC list |
| M7 | *Partly done: 68 to 49 lines.* **Dead and commented-out code**: 66 lines (`DBusMediaPlayer.vala` 14, `Display.vala` 8, `GstStreamPlayer.vala` 6, `Station.vala` 6, `DirectoryController.vala` 6) | Delete it. Git keeps the history | S | Commented-out code lines at or near 0 |
| M8 | **Stale debt markers**: 13 `TODO`/`FIXME`. Several (`by_url`, "radio-browser should handle URL queries, but is broken") predate the `by_url` parameter fix of 2026-10-21 | Re-test `by_url` and either close the TODOs or turn them into issues. Put an owner or issue number on every remaining marker | S | Marker count; none without an issue link |
| M9 | *Partly done 2026-11-06 (60 to 35 calls): `HttpClient`, `RadioBrowser`, `DirectoryController`, `PlayerController`, `StarStore` and `Settings` no longer call `app()`. What is left is mostly widgets.* **Hidden global state**: 61 `app()` calls (`PlayerController` 13, `Settings` 8, `PreferencesPopover` 8). The Jukebox controller already receives its dependencies through the constructor | Pass dependencies (events, settings, directory) into constructors instead of calling `app()`. This is also what makes M1 possible | M-L | `app()` count |
| M10 | *Partly done: 4 to 3.* **Swallowed errors**: 4 empty catch blocks (`Application.vala` 2, `StarStore.vala` 1, `DirectoryController.vala` 1) | Log at `warning` or `debug`, or handle the error | S | Empty catch blocks at 0 |
| M11 | *Done 2026-10-21 (99.7 %), see section 8.* **Public API documentation** at 73.7 % | Document the remaining public members. Extend the script to list the undocumented ones per file | S-M | Documented share at 85 % or more |
| M12 | **Compiler warnings are not tracked** | Record the warning count from a clean build in section 4 and fail CI on new ones (`-Dwarning_level=2`, `--fatal-warnings` where possible) | S | Warning count |
| M13 | **Four files are over 500 SLOC**: `HistoryButton` 602, `Display` 583, `RadioBrowser` 517, `DBusMediaPlayer` 513 (none were at release) | Split by responsibility: history list and popover in `HistoryButton`; page building in `Display`; SRV discovery in `RadioBrowser`; the property and method tables in `DBusMediaPlayer` | M | Files over 500 SLOC at 0 |

### 5.2 Performance

| # | Finding and evidence | Action | Effort | Metric to watch |
|---|---|---|---|---|
| P1 | *Done 2026-11-06: no blocking call sites are left.* **Blocking HTTP on the UI thread**: 7 call sites, all in `RadioBrowser.vala`: `click` (205), `vote` (224), `get_tags` (251), `choose_server` (420), `stats` (475), `station_query` (528), `get_srv_api_servers` (772). `click` runs on every station play through `Window.handle_play_station` -> `count_station_click`. With the 3 s session timeout, a slow or resetting server freezes the window; the logged resets arrive after about 360 ms | Make `click` and `vote` fire-and-forget with `GETasync`. Make the startup work (`stats`, `choose_server`, server discovery) and the home-list query async. Keep sync wrappers only if a caller truly needs one | M | Blocking call sites at 0 on the UI thread |
| P2 | *Done 2026-11-06: no eager debug calls are left.* **Eager debug strings**: 49 `debug(@"...")` calls (RadioBrowser 20, Jukebox 8). Vala builds the string before `debug()` can skip it. The cost matters on hot paths: `HttpClient.getSession` logs on every request (two getter calls plus a string) | Remove the debug lines from per-request and per-tick paths, or guard them behind one cheap check. Leave the cold ones alone | S | Eager debug calls in `HttpClient` at 0 |
| P3 | **Per-second timer fans out**: `TapeCounterController` emits two signals every second while playing, and at least `HistoryButton` listens. The listener already returns early when the popover is hidden, which is good | Keep it that way. Profile once to confirm nothing else does work per tick; have new listeners follow the same early-return pattern | S | Timer registrations (32); Sysprof wakeups |
| P4 | **Signal handlers are rarely disconnected**: 115 connects against 11 disconnects. Closures that capture widgets on long-lived objects (the event bus, history, directory) can keep dead widgets alive and fire after they are gone. Most at risk are widgets created repeatedly, such as station lists and search results | Audit handlers attached to long-lived objects from short-lived widgets. Disconnect on destroy or use weak references. Confirm with the 50-open-and-close memory test in section 3.3 | M | connect : disconnect ratio; memory growth |
| P5 | **Large pages are parsed field by field**: `Station.make` reads about 40 JSON members and strips each string for every station, and the home list asks for 41 rows. The cost is small per row; worth checking only if profiling shows it | Parse lazily or only the fields the lists show, if Sysprof shows time here. Do not change without a profile | S | Profile only |
| P6 | *Done 2026-11-06: the best-ranked servers are probed at the same time and the first to answer wins.* **Server selection can stall at startup**: `choose_server` checks servers one at a time with blocking requests and a 3 s timeout each | After P1, check servers asynchronously and use the first that answers | M | Startup time; blocking sites |

## 6. Suggested targets for the next release

| Metric | Now | Target |
|---|---|---|
| Maximum CC | 13 | 15 or less (met) |
| Functions over 100 SLOC (excluding the data tables) | 2 | 1 or fewer |
| Files with MI under 20 | 24 of 63 | 20 or fewer |
| Files over 500 SLOC | 4 | 0 |
| Blocking HTTP call sites on the UI thread | 0 | 0 (met) |
| Eager debug calls | 0 | 0 (met) |
| Public API documented | 99.8 % | 95 % or more (met) |
| Empty catch blocks | 3 | 0 |
| Commented-out code lines | 49 | 20 or fewer |
| Global `app()` calls | 35 | 20 or fewer |
| Tests | none | CI runs the first unit tests (M1) |
| Compiler warnings | not tracked | tracked, none new |

## 7. Limitations

* The Vala scanner is heuristic. Lambdas count toward the function that contains them, and trivial one-line
  `get`/`set` accessors are left out. Compare only runs of the same script version, and re-run the
  baseline with the current script rather than reusing old numbers.
* The maintainability index uses a token-based approximation of Halstead volume, so absolute values differ
  from other tools. Its value is in ranking files and watching the trend.
* Duplication is counted over 6-line windows of normalized lines. Repetitive data tables are ignored.
* Static counts cannot show runtime behaviour. Section 5.2 findings should be confirmed with a profile
  before large changes are made.
* The 2.2.0-beta.2 baseline is a commit, not a tag. Tag the release so the baseline is unambiguous.

### 2026-10-26: screenshot mode for debug builds

Not compiled or run when written (no compiler in the editing environment).

* New `src/Services/ScreenshotMode.vala`, compiled only under `DEBUG_LOCAL`, driven by the `TUNER_SCREENSHOT`
  environment variable. Small `#if DEBUG_LOCAL` hooks: `Application.create_main_window` (prepare and apply),
  `Application.debug_set_online`, `Window.screenshot_select_view`, `Display.select_view_by_name`.
* New `scripts/screenshots.sh` (sandboxed run per preset on a private Xvfb display, capture, crop, post-process) and `scripts/flathub_screenshots.py`
  (crop, shadow, scale, metainfo snippet).
* Cost: about 330 lines of debug-only Vala and two scripts. Release and Flatpak builds are unchanged.

### 2026-11-06: start-up, connection and structure changes

Built and run by the maintainer; no automated tests exist.

* Start-up is asynchronous: the window appears at once with the offline look, and the online look
  follows when a radio-browser server has been chosen and has answered (`ConnectionCoordinator`).
* `StartupCoordinator` owns the launch sequence (jingle, start on starred, auto-play).
* `ServerSelector` and `ServerProber` choose the server (parallel probe); `NetworkState` carries the
  online flag and the offline cancellable.
* `HttpClient` retries only failures that can clear up; the blocking `GET`/`HEAD` were removed.
* `scripts/code_metrics.py` now leaves out `Widgets/granite` and `Services/ScreenshotMode` by default.
