<!--
SPDX-FileCopyrightText: Copyright © 2026 technosf <https://github.com/technosf>

SPDX-License-Identifier: GPL-3.0-or-later
-->
# Tuner Code Quality

How Tuner's source is measured, what the numbers mean, the current scores, and where the
biggest maintainability and performance opportunities are.

* Measured: 2026-10-21, commit `f3fe620` plus the uncommitted working tree
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
python3 scripts/code_metrics.py --root src --compare /tmp/rel/src --exclude Widgets/granite --top 12

# Everything, including vendored code
python3 scripts/code_metrics.py --root src

# Machine-readable summary
python3 scripts/code_metrics.py --root src --exclude Widgets/granite --json metrics.json
```

## 2. Scope

| In scope | Out of scope |
|---|---|
| `src/**/*.vala` (60 files) | `po/` translations, `data/` resources, packaging files |
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
to read (`DataProvider.SortOrder.to_string`), and the country and language lookup tables score as
very long functions while being data, not logic.

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

Measured 2026-10-21 on commit `f3fe620` plus the uncommitted working tree (Jukebox, broken-station list, RadioBrowser and diagnostics changes). Baseline: `5b150ef` (2.2.0-beta.2). Tuner-authored code only; vendored code is in 4.6.

### 4.1 Summary: working tree against the 2.2.0-beta.2 release

| Metric | Current | Baseline | Change |
|---|---|---|---|
| Files | 56 | 53 | +3 |
| Source lines (SLOC) | 9284 | 8954 | +330 |
| Comment lines | 4592 | 4190 | +402 |
| Comment density % | 33.1 | 31.9 | +1.2 |
| Functions / methods | 521 | 496 | +25 |
| Average CC | 2.84 | 2.83 | +0.01 |
| Median CC | 2 | 2 | +0 |
| 90th percentile CC | 6 | 6 | +0 |
| Max CC | 29 | 24 | +5 |
| Functions CC > 10 | 10 | 10 | +0 |
| Functions CC > 20 | 1 | 1 | +0 |
| Functions > 50 SLOC | 17 | 17 | +0 |
| Functions > 100 SLOC | 5 | 5 | +0 |
| Functions > 5 params | 3 | 3 | +0 |
| Functions nesting > 4 | 2 | 2 | +0 |
| Files > 500 SLOC | 0 | 0 | +0 |
| Files > 1000 SLOC | 0 | 0 | +0 |
| Public API documented % | 73.7 | 72.5 | +1.2 |
| Duplicated lines % | 3.1 | 3.1 | +0 |
| Maintainability index (SLOC-weighted) | 15.4 | 15.1 | +0.3 |
| Files with MI < 20 | 20 | 20 | +0 |
| TODO/FIXME/HACK markers | 13 | 12 | +1 |
| Commented-out code lines | 66 | 68 | -2 |
| Empty catch blocks | 4 | 5 | -1 |
| Blocking HTTP call sites | 7 | 7 | +0 |
| Eager debug(@"...") calls | 49 | 33 | +16 |
| Timer / idle registrations | 32 | 33 | -1 |
| Signal connect : disconnect | 115 : 11 | 111 : 11 |  |
| Global app() calls | 61 | 60 | +1 |

### 4.2 Complexity hotspots

Highest cyclomatic complexity:

| Location | Function | CC | SLOC | Params | Max nesting |
|---|---|---|---|---|---|
| `Ext/GstStreamPlayer.vala:200` | bus_callback | 29 | 97 | 2 | 7 |
| `Services/DataProvider.vala:97` | to_string | 18 | 40 | 0 | 1 |
| `Providers/RadioBrowser.vala:738` | get_srv_api_servers | 14 | 52 | 0 | 7 |
| `Widgets/PlayingStationInfo.vala:253` | handle_metadata_changed | 14 | 41 | 2 | 2 |
| `Settings.vala:133` | save | 13 | 46 | 0 | 3 |
| `Models/Station.vala:420` | set_up_to_date_with | 13 | 27 | 1 | 1 |
| `Widgets/Display.vala:417` | initialize | 13 | 165 | 0 | 3 |
| `Ext/GstFader.vala:259` | begin_fade | 12 | 56 | 0 | 3 |
| `Models/Favicon.vala:151` | load_favicon_async | 12 | 36 | 1 | 2 |
| `Controllers/PlayerController.vala:57` | set_play_state | 11 | 50 | 1 | 3 |
| `Providers/RadioBrowser.vala:510` | station_query | 10 | 35 | 2 | 3 |
| `Providers/RadioBrowser.vala:562` | station_query_async | 10 | 36 | 2 | 3 |

Longest functions (the two `get` entries are data tables, not logic):

| Location | Function | SLOC | CC |
|---|---|---|---|
| `Models/Countries.vala:23` | get | 256 | 2 |
| `Models/Languages.vala:46` | get | 193 | 2 |
| `Widgets/Display.vala:417` | initialize | 165 | 13 |
| `Widgets/PreferencesPopover.vala:19` | construct | 123 | 4 |
| `Widgets/Display.vala:168` | Display | 102 | 4 |
| `Ext/GstStreamPlayer.vala:200` | bus_callback | 97 | 29 |
| `Widgets/HeaderBar.vala:129` | HeaderBar | 96 | 7 |
| `Widgets/PlayingStationInfo.vala:79` | PlayingStationInfo | 72 | 5 |
| `Widgets/TitleBox.vala:59` | TitleBox | 64 | 4 |
| `Services/StarStore.vala:307` | load | 63 | 9 |
| `Widgets/HistoryButton.vala:109` | build_popover | 61 | 1 |
| `Widgets/base/StationListBox.vala:149` | StationListBox | 58 | 2 |

### 4.3 Files

Largest files:

| File | SLOC | Functions | Avg CC | MI |
|---|---|---|---|---|
| `Ext/GstFader.vala` | 483 | 35 | 3.0 | 0.0 |
| `Widgets/Display.vala` | 478 | 13 | 3.6 | 4.8 |
| `Providers/RadioBrowser.vala` | 473 | 28 | 3.8 | 0.0 |
| `Application.vala` | 372 | 35 | 1.9 | 5.7 |
| `Widgets/HistoryButton.vala` | 356 | 26 | 1.8 | 7.7 |
| `Widgets/base/AnimatedIcons.vala` | 345 | 18 | 2.8 | 7.9 |
| `Widgets/Window.vala` | 338 | 24 | 1.7 | 10.0 |
| `Widgets/PlayingStationInfo.vala` | 333 | 14 | 3.8 | 8.8 |
| `Services/DBusMediaPlayer.vala` | 320 | 22 | 2.0 | 11.2 |
| `Services/StarStore.vala` | 284 | 18 | 3.1 | 10.3 |
| `Controllers/DirectoryController.vala` | 281 | 26 | 1.6 | 12.6 |
| `Models/History.vala` | 276 | 23 | 3.1 | 9.4 |

Lowest maintainability index:

| File | MI | SLOC | Total CC |
|---|---|---|---|
| `Providers/RadioBrowser.vala` | 0.0 | 473 | 106 |
| `Ext/GstFader.vala` | 0.0 | 483 | 106 |
| `Widgets/Display.vala` | 4.8 | 478 | 47 |
| `Application.vala` | 5.7 | 372 | 65 |
| `Widgets/HistoryButton.vala` | 7.7 | 356 | 48 |
| `Widgets/base/AnimatedIcons.vala` | 7.9 | 345 | 50 |
| `Widgets/PlayingStationInfo.vala` | 8.8 | 333 | 53 |
| `Models/History.vala` | 9.4 | 276 | 72 |
| `Ext/GstStreamPlayer.vala` | 9.6 | 271 | 64 |
| `Widgets/Window.vala` | 10.0 | 338 | 40 |
| `Services/StarStore.vala` | 10.3 | 284 | 55 |
| `Widgets/base/StationList.vala` | 10.8 | 267 | 57 |

### 4.4 Duplication and technical debt

Duplication between and within files (6-line windows):

| File A | File B | Shared windows |
|---|---|---|
| `Widgets/base/AnimatedIcons.vala` | `Widgets/base/AnimatedIcons.vala` | 15 |
| `Providers/RadioBrowser.vala` | `Providers/RadioBrowser.vala` | 11 |
| `Controllers/DirectoryController.vala` | `Controllers/DirectoryController.vala` | 5 |
| `Services/HttpClient.vala` | `Services/HttpClient.vala` | 2 |
| `Ext/GstFader.vala` | `Ext/GstFader.vala` | 2 |
| `Models/StationListBoxConfig.vala` | `Widgets/base/StationListBox.vala` | 2 |

Debt markers:

| Location | Marker |
|---|---|
| `Services/DataProvider.vala:278` | //public abstract Set<Model.Station> by_url(string url) throws DataError;  // TODO Not wor |
| `Models/Station.vala:427` | //  && (this.changeuuid == p.changeuuid) // TODO Radio browser changeuuids broken |
| `Models/StreamPlayer.vala:94` | // FIXME |
| `Controllers/DirectoryController.vala:86` | * @todo radio-browser should handle multiple UUID on a query, but is broken |
| `Controllers/DirectoryController.vala:102` | * @brief Get a collection of Station station by its stream URL. // TODO Not working at Pro |
| `Controllers/DirectoryController.vala:106` | * @todo radio-browser should handle URL queries, but is broken |
| `Controllers/DirectoryController.vala:446` | // TODO Place filter here? |
| `Controllers/DirectoryController.vala:478` | // TODO Place filter here? |
| `Widgets/Display.vala:436` | // true // TODO Implement filter |
| `Widgets/Display.vala:802` | // true // TODO Implement filter |
| `Widgets/Window.vala:142` | //this.resize(900, 600);  // FIXME Comment out |
| `Widgets/base/StationList.vala:89` | // FIXME Wraps stations in StationButtons, adds to flowbox |
| `Widgets/base/StationListBoxContent.vala:11` | // FIXME Refactor content out to a model - can it be shard with search? |

Commented-out code by file: `Services/DBusMediaPlayer.vala` 14, `Widgets/Display.vala` 8, `Ext/GstStreamPlayer.vala` 6, `Models/Station.vala` 6, `Controllers/DirectoryController.vala` 6, `Widgets/base/CyclingRevealLabel.vala` 4, `Application.vala` 3, `Providers/RadioBrowser.vala` 3

### 4.5 Anti-pattern scan

| Check | Meaning | Count | Top files |
|---|---|---|---|
| sync_http_get | Blocking HTTP on the calling (usually UI) thread | 7 | `Providers/RadioBrowser.vala` 7 |
| eager_debug | debug(@"...") builds its string even when debug logging is off | 49 | `Providers/RadioBrowser.vala` 20, `Controllers/JukeboxController.vala` 8, `Utils.vala` 3, `Services/HttpClient.vala` 3 |
| timers | Timers / idle callbacks (check each is removed) | 32 | `Ext/GstFader.vala` 6, `Widgets/PlayingStationInfo.vala` 6, `Application.vala` 4, `Widgets/base/CyclingRevealLabel.vala` 3 |
| connects | Signal connections | 115 | `Widgets/Display.vala` 19, `Widgets/HeaderBar.vala` 11, `Widgets/HistoryButton.vala` 9, `Widgets/base/StationList.vala` 8 |
| disconnects | Signal disconnections | 11 | `Controllers/PlayerController.vala` 3, `Coordinators/PlaybackRecoveryCoordinator.vala` 2, `Coordinators/UsageTrackingCoordinator.vala` 2, `Widgets/StationButton.vala` 2 |
| empty_catch | Empty catch blocks (swallowed errors) | 4 | `Application.vala` 2, `Services/StarStore.vala` 1, `Controllers/DirectoryController.vala` 1 |
| app_global | Global app() accessor calls (hidden coupling) | 61 | `Controllers/PlayerController.vala` 13, `Settings.vala` 8, `Widgets/PreferencesPopover.vala` 8, `Controllers/DirectoryController.vala` 5 |
| to_array | Collection copies via to_array() | 5 | `Providers/RadioBrowser.vala` 2, `Controllers/DirectoryController.vala` 2, `Controllers/JukeboxController.vala` 1 |
| sleep | Thread sleeps | 0 |  |

Blocking HTTP call sites: `Providers/RadioBrowser.vala:205`, `Providers/RadioBrowser.vala:224`, `Providers/RadioBrowser.vala:251`, `Providers/RadioBrowser.vala:420`, `Providers/RadioBrowser.vala:475`, `Providers/RadioBrowser.vala:528`, `Providers/RadioBrowser.vala:772`

### 4.6 Vendored code (`src/Widgets/granite`)

4 files, 2038 SLOC, 167 functions, highest CC 21. Not owned by Tuner, so it is kept out of the scores above. Upstream fixes should be taken from the Granite project instead of edited in place.


### 4.7 What the scores say

* **Function-level complexity is healthy.** Median CC is 2 and the 90th percentile is 6. Only 10 of 521
  functions exceed 10, and one exceeds 20. Complexity is concentrated in a few functions, so it is cheap to fix.
* **File-level maintainability is the weak spot.** 20 of 56 files score below 20 on the maintainability
  index. The worst are `RadioBrowser.vala` and `GstFader.vala` (both 0.0, total CC 106 each), then
  `Display.vala` (4.8) and `Application.vala` (5.7). These are large files with many responsibilities, not
  files with convoluted individual functions.
* **Since the 2.2.0-beta.2 release the code base grew by 330 SLOC and stayed level.** Average and median
  CC, the long-function counts, duplication (3.1 %) and the maintainability index (15.1 to 15.4) did not
  move. Empty catch blocks fell from 5 to 4.
* **Two numbers moved the wrong way.** The maximum CC rose from 24 to 29: `GstStreamPlayer.bus_callback`
  was already the worst function at release (CC 24) and the playback-error diagnostics added during this
  work took it to 29. Eager `debug(@"...")` calls rose from 33 to 49 (RadioBrowser logging and the new
  Jukebox controller).
* **No tests exist**, so none of the figures above are backed by an automated safety net.
* **Documentation of the public API is at 73.7 %**, below the 85 % target.

## 5. Opportunities

Ordered by value for the effort. "Effort": S is under half a day, M is one or two days, L is a week or more.
The last column is the metric in section 4 that should move.

### 5.1 Maintainability

| # | Finding and evidence | Action | Effort | Metric to watch |
|---|---|---|---|---|
| M1 | **No automated tests.** There is no `test()` in `meson.build` and no `tests/` folder | Add a `tests/` folder with GLib tests (`GLib.Test`) and a meson `test()` target. First candidates, all pure logic: `StationSession`, `RadioBrowser.get_search_query_params`, `Station.make` JSON parsing, `StationSet` paging, `DataProvider.SortOrder.to_string` | M | Tests run in CI; coverage reported |
| M2 | **`GstStreamPlayer.bus_callback`**: CC 29, 97 SLOC, nesting 7 (`Ext/GstStreamPlayer.vala:200`) | Split the big `switch` into one handler per message type (`on_error`, `on_state_changed`, `on_tag`, ...) and move the error-logging block into a helper such as `describe_gst_error()` | S | Max CC under 15; nesting under 4 |
| M3 | **`RadioBrowser.vala`** is 473 SLOC with MI 0.0 and total CC 106. It does server discovery, failover, query building, HTTP and JSON parsing. `station_query` and `station_query_async` are near copies (CC 10 each) | Split into server discovery and failover, query building, and response parsing. Make the sync query a wrapper around the async one, or retire the sync one once callers are async (see P1). That also removes the duplication inside the file | M-L | MI above 20; one copy of the retry logic |
| M4 | **`Display.vala`**: 478 SLOC, MI 4.8, `initialize` 165 SLOC (CC 13), constructor 102 SLOC, 19 signal connections. A `FIXME` in `StationListBoxContent.vala` already asks for the content to move out to a model | Break `initialize` into builders (sidebar categories, search, saved searches). Keep moving behaviour out of the widget into controllers, as was done for Jukebox | M | Longest-function list; MI |
| M5 | **`GstFader.vala`** is 483 SLOC, MI 0.0, six timers, and is created by `GstStreamPlayer` as a shared fader (`GstStreamPlayer.vala:400`). The crossfade API in `GstStreamPlayer` is commented out | Check whether crossfade is still used by the UI. If only fade in/out remains, trim the class to that. Otherwise split the curves, timing and playbin handling | M | SLOC; MI; timer count |
| M6 | **Data in code**: `Countries.get` is 256 SLOC and `Languages.get` is 193 SLOC. `SortOrder.to_string` is a CC-18 switch | Move the country and language tables to a resource file (JSON or CSV in the GResource bundle). Replace `to_string` with a lookup | S-M | Longest-function list; CC list |
| M7 | **Dead and commented-out code**: 66 lines (`DBusMediaPlayer.vala` 14, `Display.vala` 8, `GstStreamPlayer.vala` 6, `Station.vala` 6, `DirectoryController.vala` 6) | Delete it. Git keeps the history | S | Commented-out code lines at or near 0 |
| M8 | **Stale debt markers**: 13 `TODO`/`FIXME`. Several (`by_url`, "radio-browser should handle URL queries, but is broken") predate the `by_url` parameter fix of 2026-10-21 | Re-test `by_url` and either close the TODOs or turn them into issues. Put an owner or issue number on every remaining marker | S | Marker count; none without an issue link |
| M9 | **Hidden global state**: 61 `app()` calls (`PlayerController` 13, `Settings` 8, `PreferencesPopover` 8). The Jukebox controller already receives its dependencies through the constructor | Pass dependencies (events, settings, directory) into constructors instead of calling `app()`. This is also what makes M1 possible | M-L | `app()` count |
| M10 | **Swallowed errors**: 4 empty catch blocks (`Application.vala` 2, `StarStore.vala` 1, `DirectoryController.vala` 1) | Log at `warning` or `debug`, or handle the error | S | Empty catch blocks at 0 |
| M11 | *Done 2026-10-21 (99.7 %), see section 8.* **Public API documentation** at 73.7 % | Document the remaining public members. Extend the script to list the undocumented ones per file | S-M | Documented share at 85 % or more |
| M12 | **Compiler warnings are not tracked** | Record the warning count from a clean build in section 4 and fail CI on new ones (`-Dwarning_level=2`, `--fatal-warnings` where possible) | S | Warning count |

### 5.2 Performance

| # | Finding and evidence | Action | Effort | Metric to watch |
|---|---|---|---|---|
| P1 | *Partly done 2026-10-21, see section 8.* **Blocking HTTP on the UI thread**: 7 call sites, all in `RadioBrowser.vala`: `click` (205), `vote` (224), `get_tags` (251), `choose_server` (420), `stats` (475), `station_query` (528), `get_srv_api_servers` (772). `click` runs on every station play through `Window.handle_play_station` -> `count_station_click`. With the 3 s session timeout, a slow or resetting server freezes the window; the logged resets arrive after about 360 ms | Make `click` and `vote` fire-and-forget with `GETasync`. Make the startup work (`stats`, `choose_server`, server discovery) and the home-list query async. Keep sync wrappers only if a caller truly needs one | M | Blocking call sites at 0 on the UI thread |
| P2 | *Done for the hot paths 2026-10-21, see section 8.* **Eager debug strings**: 49 `debug(@"...")` calls (RadioBrowser 20, Jukebox 8). Vala builds the string before `debug()` can skip it. The cost matters on hot paths: `HttpClient.getSession` logs on every request (two getter calls plus a string) | Remove the debug lines from per-request and per-tick paths, or guard them behind one cheap check. Leave the cold ones alone | S | Eager debug calls in `HttpClient` at 0 |
| P3 | **Per-second timer fans out**: `TapeCounterController` emits two signals every second while playing, and at least `HistoryButton` listens. The listener already returns early when the popover is hidden, which is good | Keep it that way. Profile once to confirm nothing else does work per tick; have new listeners follow the same early-return pattern | S | Timer registrations (32); Sysprof wakeups |
| P4 | **Signal handlers are rarely disconnected**: 115 connects against 11 disconnects. Closures that capture widgets on long-lived objects (the event bus, history, directory) can keep dead widgets alive and fire after they are gone. Most at risk are widgets created repeatedly, such as station lists and search results | Audit handlers attached to long-lived objects from short-lived widgets. Disconnect on destroy or use weak references. Confirm with the 50-open-and-close memory test in section 3.3 | M | connect : disconnect ratio; memory growth |
| P5 | **Large pages are parsed field by field**: `Station.make` reads about 40 JSON members and strips each string for every station, and the home list asks for 41 rows. The cost is small per row; worth checking only if profiling shows it | Parse lazily or only the fields the lists show, if Sysprof shows time here. Do not change without a profile | S | Profile only |
| P6 | **Server selection can stall at startup**: `choose_server` checks servers one at a time with blocking requests and a 3 s timeout each | After P1, check servers asynchronously and use the first that answers | M | Startup time; blocking sites |

## 6. Suggested targets for the next release

| Metric | Now | Target |
|---|---|---|
| Maximum CC | 29 | 20 or less |
| Functions over 100 SLOC (excluding the data tables) | 3 | 1 or fewer |
| Files with MI under 20 | 20 of 56 | 16 or fewer |
| Blocking HTTP call sites on the UI thread | 7 | 3 or fewer (startup only) |
| Eager debug calls in `HttpClient` | 3 | 0 |
| Public API documented | 73.7 % | 80 % or more |
| Empty catch blocks | 4 | 0 |
| Commented-out code lines | 66 | 20 or fewer |
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
