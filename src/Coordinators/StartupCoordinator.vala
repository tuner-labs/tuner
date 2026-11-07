/**
 * SPDX-FileCopyrightText: Copyright © 2026 <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file StartupCoordinator.vala
 */

using Tuner.Controllers;
using Tuner.Events;
using Tuner.Models;
using Tuner.Widgets;

namespace Tuner.Coordinators {

	/**
	 * @brief Coordinates startup flows that span multiple components.
	 *
	 * Everything that happens once per launch, in one place:
	 * - The startup jingle, as soon as the main loop is free after the window is created. Auto-play waits for it to finish, so that
 *   the station does not start over the jingle.
	 * - Starting on the starred stations, if the user asked for that.
	 * - Auto-play of the last played station, once the connection is ready (the network is up and a
	 *   radio-browser server has answered, see ConnectionCoordinator).
	 */
	public class StartupCoordinator : GLib.Object
	{
		/** @brief The jingle is played at this fraction of the user's volume */
		private const double JINGLE_VOLUME_FACTOR = 0.5;

		/** @brief The sound played at start-up */
		private const string JINGLE_URI = "resource:///io/github/tuner_labs/tuner/sounds/tuner_startup.mp3";

		/** @brief Auto-play stops waiting for the jingle after this long, in case it never reports being done */
		private const uint JINGLE_MAX_MS = 12000;

		/** @brief Milliseconds to wait before the one retry of a lookup that found nothing */
		private const uint LOOKUP_RETRY_MS = 2000;

		/** @brief Where the auto-play flow has got to */
		private enum Autoplay
		{
			IDLE,       // Not asked for, or nothing to play
			WAITING,    // Waiting for the connection to be ready
			DONE        // Started: the flow runs once per session
		}

		private Application _app;
		private AppEventBus _events;
		private Window _window;
		private Settings _settings;
		private DirectoryController _directory;

		private Autoplay _autoplay = Autoplay.IDLE;
		private ulong _state_handler_id = 0;
		private GLib.Object? _jingle = null;      // The jingle player while it is playing
		private bool _jingle_busy = false;        // The jingle is due or playing: auto-play waits


		/**
		 * @brief Creates a startup coordinator bound to the app event bus.
		 *
		 * @param app Application context, for the connection state.
		 * @param events App-level event bus used for connection events.
		 * @param window Main window used to dispatch station playback.
		 * @param settings Application settings that control auto-play behavior.
		 * @param directory Directory controller used to resolve last station UUID.
		 */
		public StartupCoordinator (
			Application app,
			AppEventBus events,
			Window window,
			Settings settings,
			DirectoryController directory
		) {
			Object();
			_app = app;
			_events = events;
			_window = window;
			_settings = settings;
			_directory = directory;
		} // StartupCoordinator


		/**
		 * @brief Starts the startup workflows managed by this coordinator.
		 *
		 * Call once, right after the main window has been created.
		 */
		public void start()
		{
			start_jingle();
			start_on_starred();
			start_autoplay();
		} // start


		/**
		 * @brief Plays the startup jingle as soon as the main loop is free, if the user wants it.
		 *
		 * The setting is checked when the time comes, so changing it in the meantime counts.
		 * Auto-play is held back until the jingle has finished.
		 */
		private void start_jingle()
		{
			_jingle_busy = _settings.startup_jingle;

			GLib.Idle.add_once (() => {
				if (_jingle != null || !_settings.startup_jingle)
				{
					jingle_finished ();
					return;
				}

				_jingle = StreamPlayer.play_file (JINGLE_URI, _settings.volume * JINGLE_VOLUME_FACTOR, () => {
					_jingle = null;
					jingle_finished ();
				});
				if (_jingle == null)
					jingle_finished ();         // The player could not be set up
			});

			// A jingle that never reports being done must not hold up auto-play for ever
			GLib.Timeout.add_once (JINGLE_MAX_MS, () => { jingle_finished (); });
		} // start_jingle


		/**
		 * @brief The jingle is over, or was never going to play: auto-play may go ahead.
		 */
		private void jingle_finished ()
		{
			_jingle_busy = false;
			try_autoplay ();
		} // jingle_finished


		/**
		 * @brief Has the window show the starred stations first, if the user asked for that.
		 *
		 * Safe to do before the window is active: the choice is remembered until it is.
		 */
		private void start_on_starred()
		{
			if (_settings.start_on_starred)
				_window.choose_starred_stations();
		} // start_on_starred


		/**
		 * @brief Plays the last played station as soon as the connection is ready, if auto-play is on.
		 *
		 * Now if the connection already is ready, otherwise when it becomes so.
		 */
		private void start_autoplay()
		{
			if (!_settings.auto_play || _settings.last_played_station.strip().length == 0)
				return;

			_autoplay = Autoplay.WAITING;
			_state_handler_id = _events.connection_state_changed_sig.connect((state) => {
				try_autoplay();
			});
			try_autoplay();
		} // start_autoplay


		/**
		 * @brief Starts auto-play if it is waiting, the connection is ready and the jingle is over.
		 *
		 * Runs at most once per session.
		 */
		private void try_autoplay()
		{
			if (_autoplay != Autoplay.WAITING || _app.connection.state != ConnectionState.READY || _jingle_busy)
				return;

			_autoplay = Autoplay.DONE;
			stop_listening();

			_directory.load();          // Starred stations and saved searches
			autoplay_last_station.begin();
		} // try_autoplay


		/**
		 * @brief Looks up the last played station and plays it, without blocking startup.
		 *
		 * A lookup that finds nothing is tried once more after a short wait, in case the first
		 * request was caught by a server hiccup.
		 */
		private async void autoplay_last_station()
		{
			for (int attempt = 0; attempt < 2; attempt++)
			{
				if (attempt > 0)
				{
					yield nap(LOOKUP_RETRY_MS);
					if (_app.connection.state != ConnectionState.READY)
						return;
				}

				try
				{
					var page = yield _directory.load_station_uuid(_settings.last_played_station).next_page_async();
					if (page != null)
					{
						foreach (var station in page)
						{
							_window.handle_play_station(station);
							return;
						}
					}
				}
				catch (SourceError e)
				{
					if (Tuner.debug_enabled ())
						debug(@"Auto-play lookup failed: $(e.message)");
				}
			}
			warning("Auto-play: the last played station could not be found");
		} // autoplay_last_station


		private void stop_listening()
		{
			if (_state_handler_id > 0)
			{
				_events.disconnect(_state_handler_id);
				_state_handler_id = 0;
			}
		} // stop_listening


		/**
		 * @brief Disconnects coordinator event handlers and releases resources.
		 */
		public override void dispose()
		{
			stop_listening();
			base.dispose();
		} // dispose
	} // StartupCoordinator
} // Tuner.Coordinators
