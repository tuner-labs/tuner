/**
 * SPDX-FileCopyrightText: Copyright © 2026 <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file PlaybackRecoveryCoordinator.vala
 */

using Tuner.Controllers;
using Tuner.Ext;
using Tuner.Events;
using Tuner.Models;

namespace Tuner.Coordinators {

	/**
	 * @brief Coordinates restart-after-outage playback behavior.
	 */
	public class PlaybackRecoveryCoordinator : GLib.Object
	{
		private Application _app;
		private AppEventBus _events;
		private PlayerController _player;
		private Settings _settings;

		private bool _was_playing_before_offline = false;
		private ulong _connectivity_handler_id = 0;
		private ulong _player_state_handler_id = 0;


		/**
			* @brief Creates a playback recovery coordinator.
			*
			* @param app Application context used for connectivity state checks.
			* @param events App-level event bus used for connectivity changes.
			* @param player Player controller used to inspect and restart playback.
			* @param settings Application settings controlling recovery behavior.
			*/
		public PlaybackRecoveryCoordinator (
			Application app,
			AppEventBus events,
			PlayerController player,
			Settings settings
		) {
			Object();
			_app = app;
			_events = events;
			_player = player;
			_settings = settings;

			_connectivity_handler_id = _events.connectivity_changed_sig.connect((is_online ) => {
				on_connectivity_changed(is_online );
			});

			_player_state_handler_id = _events.state_changed_sig.connect((station, state) => {
				on_player_state_changed(station, state);
			});
			}


			/**
			 * @brief Handles connectivity transitions for playback recovery.
			 *
			 * On offline transition, remembers whether playback was active.
			 * On online transition, optionally restarts playback if enabled.
			 *
			 * @param is_online True when app has network connectivity.
			 * @param is_offline True when app has no network connectivity.
			 */
			private void on_connectivity_changed(bool is_online )
			{
				if (is_online)
				{
					bool already_playing = _player.player_state == PlayerInterface.State.PLAYING
						|| _player.player_state == PlayerInterface.State.BUFFERING;
					if (_settings.play_restart && _was_playing_before_offline && _player.can_play() && !already_playing)
						_player.play_station(_player.station);
					_was_playing_before_offline = false;
				}
				else
				{
					_was_playing_before_offline = _was_playing_before_offline
						|| _player.player_state == PlayerInterface.State.PLAYING
						|| _player.player_state == PlayerInterface.State.BUFFERING;
				}
			} // on_connectivity_changed


			/**
			 * @brief Tracks player state to refine recovery decisions.
			 *
			 * @param station Current station associated with the state change.
			 * @param state Current player state.
			 */
			private void on_player_state_changed(Station station, PlayerInterface.State state)
			{
			if (state == PlayerInterface.State.PLAYING || state == PlayerInterface.State.BUFFERING)
				_was_playing_before_offline = true;

			if (_app.is_online && state == PlayerInterface.State.STOPPED)
				_was_playing_before_offline = false;
			}


			/**
			 * @brief Disconnects coordinator signal handlers and releases resources.
			 */
			public override void dispose()
			{
			if (_connectivity_handler_id > 0)
			{
				_events.disconnect(_connectivity_handler_id);
				_connectivity_handler_id = 0;
			}

			if (_player_state_handler_id > 0)
			{
				_events.disconnect(_player_state_handler_id);
				_player_state_handler_id = 0;
			}

			base.dispose();
		}
	}
}
