<!--
SPDX-FileCopyrightText: Copyright © 2026 technosf <https://github.com/technosf>

SPDX-License-Identifier: GPL-3.0-or-later
-->
# Event Architecture

This document tracks the event orchestration introduced in the 2026 refactor.

## Files and Responsibilities

- `src/Events/AppEventBus.vala`
  - Defines typed cross-component application signals.
  - Current signals:
    - `connectivity_changed_sig(bool is_online)` (the network only)
    - `connection_state_changed_sig(ConnectionState)` (offline, connecting or ready: network up and a
      radio-browser server has answered)
    - `starred_stations_changed_sig(Station)`
    - `station_changed_sig(Station)`
    - `volume_changed_sig(double)`
    - `playback_time_tick_sig(Station, int total_seconds, int station_seconds)`
    - `tape_counter_sig(Station)`
    - `shuffle_mode_sig(bool)` (jukebox mode on or off)
    - `shuffle_requested_sig()`
    - `player_state_changed_sig(Station, StreamPlayer.State)`
    - `playback_metadata_changed_sig(Station, StreamMetadata)`
  - The MPRIS service (`src/Services/DBusMediaPlayer.vala`) listens to the player state, metadata, volume,
    shuffle and connectivity signals to keep clients up to date.

- `src/Coordinators/ConnectionCoordinator.vala`
  - Owns "can Tuner use the network yet?". Watches `connectivity_changed_sig`, chooses and proves a
    radio-browser server in the background, retries every few seconds while the network is up and no
    server answers, and publishes one `ConnectionState`: `OFFLINE`, `CONNECTING` or `READY`.
  - Started by `Application.activate()` before the window is built, so the window sees the real state.
  - The online look, and any work that needs the network, waits for `READY` instead of working it out
    separately. `NetworkState` (`Application.network`) holds the plain network flags and the offline
    `Cancellable`; `HttpClient`, `RadioBrowser` and `DirectoryController` are given it and use it to refuse
    requests, and `Application.is_online`/`is_offline` read through to it.

- `src/Coordinators/StartupCoordinator.vala`
  - Owns startup workflow orchestration.
  - Current workflow:
    - the startup jingle, a short delay after the window is created
    - starting on the starred stations, if the user asked for that
    - autoplay of last station
    - waits for the connection to be `READY` before the attempt
    - attempts autoplay once per app start, retrying a lookup that found nothing once

- `src/Coordinators/PlaybackRecoveryCoordinator.vala`
  - Owns restart-after-outage playback behavior.
  - Tracks whether playback was active before loss of connectivity.
  - Restarts playback on reconnect when `settings.play_restart` is enabled.

- `src/Coordinators/UsageTrackingCoordinator.vala`
  - Owns provider click/vote updates driven by player events.
  - Handles both play-start click tracking and periodic tape-counter tracking.

- `src/Application.vala`
  - Owns the shared `events` bus instance.
  - Emits `connectivity_changed_sig` when `is_online`/`is_offline` changes.
  - Instantiates coordinators:
    - `ConnectionCoordinator` and `PlaybackRecoveryCoordinator` during app construction.
    - `UsageTrackingCoordinator` during app construction.
    - `StartupCoordinator` after creating the main window.

- `src/Widgets/Window.vala`
  - Consumes the connection state to update interactive window state (online look only when `READY`).
  - No longer owns autoplay orchestration.

- `src/Widgets/HeaderBar.vala`
  - Consumes the connection state and player-state events for control-state updates.
  - No longer owns restart-after-outage orchestration.

- `src/meson.build`
  - Registers the new event/coordinator source files in build inputs.

## Event Flow (Connectivity)

1. `Application` detects network change.
2. `Application` updates `is_online` and `is_offline`.
3. `Application` emits `events.connectivity_changed_sig(...)`.
4. Subscribers react:
   - `ConnectionCoordinator` sets the connection state (offline at once; connecting, then ready when a
     server answers) and emits `connection_state_changed_sig`.
   - `Window` and `HeaderBar` listen to that state: `Window` updates active UI state and `HeaderBar`
     the visual controls.
   - `PlaybackRecoveryCoordinator` manages restart-after-outage behavior.
   - `StartupCoordinator` starts autoplay when the state is `READY`.

## Design Notes

- Keep local widget events in widget files.
- Use `AppEventBus` for cross-component events that otherwise create tight coupling.
- Use coordinators for workflows that span UI + services + application state.

## Window Action Handling

- `src/Widgets/Window.vala` now centralizes action-state initialization with:
  - `sync_action_states_from_settings()`
- Boolean toggle actions now use a shared path:
  - `toggle_setting_action(...)`
- This reduces copy/paste logic across action handlers and lowers the chance of mismatched setting/action wiring.

## Search Debounce Ownership

- `src/Widgets/TitleBox.vala`
  - Emits `searching_for_sig` immediately on text change. Pressing Return keeps the search open and
    re-runs the query; the search panel is closed by the header bar search button.
  - No longer owns debounce timers.
- `src/Controllers/SearchController.vala`
  - Owns debounce and pending-search cancellation.
  - Uses configured `_max_search_results` instead of a hardcoded limit.
- `src/Widgets/Display.vala`
  - Receives search focus/query via explicit methods:
    - `on_search_focused()`
    - `on_search_requested(string text)`
  - No longer routes search input through internal self-signals.

## Application Bootstrap Decomposition

- `src/Application.vala`
  - Keeps construct-only property assignment in the `construct` block.
  - Splits initialization responsibilities into helper methods:
    - runtime storage preparation + migration
    - connectivity monitoring setup
    - core service factory helpers
    - coordinator initialization
    - action registration helpers
  - Activation flow is split into explicit lifecycle helpers:
    - `initialize_runtime_presentation()`
    - `apply_runtime_preferences()`
    - `create_main_window()`

## Window Connectivity UI State

- `src/Widgets/Window.vala`
  - `check_online_status()` now delegates UI transitions to:
    - `apply_offline_ui_state()`
    - `apply_online_ui_state()`
  - Keeps online/offline behavior explicit and reduces branching complexity.

## Display API Cleanup

- `src/Widgets/Display.vala`
  - Removed unused public signals:
    - `favourites_changed_sig`
    - `refresh_starred_stations_sig`
  - Keeps the public event surface aligned with active call paths.

## Dependency Injection Sweep

- Replaced singleton `app()` lookups with injected references in:
  - `src/Widgets/HeaderBar.vala`
  - `src/Widgets/Display.vala`
  - `src/Services/DBusMediaPlayer.vala`
- Constructors and initializers now receive required collaborators explicitly
  (`Application`, `PlayerController`, `DataProvider.API`, `StarStore`), reducing
  hidden coupling and startup-order risk.

## Coordinator Connectivity Injection

- Removed remaining coordinator singleton lookups by injecting `Application`
  explicitly into:
  - `src/Coordinators/StartupCoordinator.vala`
  - `src/Coordinators/PlaybackRecoveryCoordinator.vala`
- `StartupCoordinator.try_autoplay()` now checks `_app.connection.state`.
- `PlaybackRecoveryCoordinator.on_player_state_changed()` now checks
  `_app.is_online`.
- `src/Application.vala` constructor wiring now passes `this` into coordinator
  constructors, making coordinator connectivity decisions explicit and testable.
