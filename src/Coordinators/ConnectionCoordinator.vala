/**
 * SPDX-FileCopyrightText: Copyright © 2026 <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file ConnectionCoordinator.vala
 */

using Tuner.Events;
using Tuner.Services;

namespace Tuner.Coordinators {

	/**
	 * @brief Owns the answer to "can Tuner use the network yet?".
	 *
	 * The network being up is not enough: a radio-browser server must also have been chosen and
	 * have answered. This coordinator watches the network, proves a server in the background,
	 * retries while the network is up and no server answers, and publishes one state:
	 *
	 * - OFFLINE: no network.
	 * - CONNECTING: network up, no server proven yet.
	 * - READY: network up and a server has answered.
	 *
	 * Everything that changes its look or starts network work listens to
	 * AppEventBus.connection_state_changed_sig, or reads state, instead of working this out for itself.
	 * Application.is_online / is_offline stay as the plain network flags used to refuse requests.
	 */
	public class ConnectionCoordinator : GLib.Object
	{
		/** @brief Seconds before the first new try when no server answered; it doubles with each failure */
		private const uint RETRY_S = 5;

		/** @brief The longest wait between tries */
		private const uint RETRY_MAX_S = 30;

		private Application _app;
		private AppEventBus _events;
		private DataProvider.API _provider;

		private ulong _connectivity_handler_id = 0;
		private bool _proving      = false;   // A server choice is under way
		private bool _prove_again  = false;   // The network came back during a choice: choose again at once
		private uint _retry_id     = 0;       // Pending retry of the server choice
		private uint _failures     = 0;       // Server choices in a row in which nothing answered
		private int64 _started_at  = 0;       // For the start-up timing line


		/** @brief The current connection state */
		public ConnectionState state { get; private set; default = ConnectionState.OFFLINE; }


		/**
		 * @brief Creates a connection coordinator
		 *
		 * @param app Application, for the network flags.
		 * @param events App-level event bus; connectivity is read from it and the state is published on it.
		 * @param provider Data provider whose server is chosen.
		 */
		public ConnectionCoordinator (Application app, AppEventBus events, DataProvider.API provider)
		{
			Object ();
			_app      = app;
			_events   = events;
			_provider = provider;

			_connectivity_handler_id = _events.connectivity_changed_sig.connect ((is_online) =>
			{
				on_connectivity_changed (is_online);
			});
		} // ConnectionCoordinator


		/**
		 * @brief Works out the starting state and, if the network is up, starts proving a server.
		 *
		 * Called once, before the window is built, so the window sees the real starting state.
		 */
		public void start ()
		{
			_started_at = GLib.get_monotonic_time ();
			on_connectivity_changed (_app.is_online);
		} // start


		/**
		 * @brief Reacts to the network going up or down.
		 */
		private void on_connectivity_changed (bool is_online)
		{
			if (!is_online)
			{
				cancel_retry ();
				change_state (ConnectionState.OFFLINE);
				return;
			}

			if (_provider.status == DataProvider.API.Status.OK)
			// A server was proven earlier: nothing to prove again
			{
				change_state (ConnectionState.READY);
				return;
			}

			change_state (ConnectionState.CONNECTING);
			if (_proving)
				_prove_again = true;     // The running choice may have been cancelled by the outage
			else
			{
				// The network has changed, so start from scratch: new connections, the normal time-out
				_failures = 0;
				HttpClient.use_fresh_session (0);
				prove ();
			}
		} // on_connectivity_changed


		/**
		 * @brief Chooses a server in the background and moves to READY when one answers.
		 */
		private void prove ()
		{
			if (_proving)
				return;

			cancel_retry ();
			_proving     = true;
			_prove_again = false;

			_provider.initialize_async.begin ((obj, res) =>
			{
				var ok = _provider.initialize_async.end (res);
				_proving = false;

				if (!_app.is_online)
				{
					change_state (ConnectionState.OFFLINE);
					return;
				}

				if (ok)
				{
					if (_failures > 0)
					{
						_failures = 0;
						HttpClient.use_fresh_session (0);       // Back to the normal time-out
					}
					if (Tuner.debug_enabled ())
						debug (@"[startup] connection ready $((GLib.get_monotonic_time () - _started_at) / 1000)ms after start");
					change_state (ConnectionState.READY);
					return;
				}

				change_state (ConnectionState.CONNECTING);
				if (_prove_again)
					prove ();
				else
					retry_later ();
			});
		} // prove


		/**
		 * @brief Notes that no server answered and tries again after a wait that grows with each failure.
		 *
		 * Each new try uses a fresh HTTP session with a longer time-out than the last, and the provider
		 * probes every server, so a stuck connection, a slow network or a few unlucky servers do not keep
		 * the app waiting for ever.
		 */
		private void retry_later ()
		{
			_failures++;
			uint wait_s = uint.min (RETRY_S << (uint.min (_failures, 8) - 1), RETRY_MAX_S);
			warning (@"No $(_provider.name ().split ("\n")[0]) server answered ($(_failures) in a row); trying again in $(wait_s)s with a fresh connection");
			HttpClient.use_fresh_session ((int) _failures);
			schedule_retry (wait_s);
		} // retry_later


		private void schedule_retry (uint wait_s)
		{
			cancel_retry ();
			_retry_id = Timeout.add_seconds (wait_s, () =>
			{
				_retry_id = 0;
				if (_app.is_online)
					prove ();
				return Source.REMOVE;
			});
		} // schedule_retry


		private void cancel_retry ()
		{
			if (_retry_id != 0)
			{
				Source.remove (_retry_id);
				_retry_id = 0;
			}
		} // cancel_retry


		/**
		 * @brief Changes the state and tells everyone, if it is different.
		 */
		private void change_state (ConnectionState new_state)
		{
			if (new_state == state)
				return;

			state = new_state;
			if (Tuner.debug_enabled ())
				debug (@"Connection state: $(new_state.label ())");
			_events.connection_state_changed_sig (new_state);
		} // change_state


		/**
		 * @brief Disconnects handlers and timers.
		 */
		public override void dispose ()
		{
			cancel_retry ();
			if (_connectivity_handler_id > 0)
			{
				_events.disconnect (_connectivity_handler_id);
				_connectivity_handler_id = 0;
			}
			base.dispose ();
		} // dispose
	} // ConnectionCoordinator
} // Tuner.Coordinators
