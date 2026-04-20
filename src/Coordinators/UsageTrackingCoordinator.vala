/**
 * SPDX-FileCopyrightText: Copyright © 2026 <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file UsageTrackingCoordinator.vala
 */

using Tuner.Controllers;
using Tuner.Ext;
using Tuner.Events;
using Tuner.Models;
using Tuner.Services;

namespace Tuner.Coordinators {

	/**
	 * @brief Coordinates provider click/vote tracking from player events.
	 */
	public class UsageTrackingCoordinator : GLib.Object
	{
		private Settings _settings;
		private AppEventBus _events;
		private DataProvider.API _provider;

		private ulong _player_state_handler_id = 0;
		private ulong _player_tape_handler_id = 0;


		/**
		 * @brief Creates a usage tracking coordinator for player-driven provider events.
		 *
		 * @param settings Application settings that gate vote/click behavior.
		 * @param events App-level event bus used for player lifecycle signals.
		 * @param provider Data provider that receives click/vote notifications.
		 */
		public UsageTrackingCoordinator(
			Settings settings,
			AppEventBus events,
			DataProvider.API provider
		) {
			Object();
			_settings = settings;
			_events = events;
			_provider = provider;

			_player_state_handler_id = _events.player_state_changed_sig.connect((station, state) => {
				on_player_state_changed(station, state);
			});

			_player_tape_handler_id = _events.tape_counter_sig.connect((station) => {
				on_tape_counter(station);
			});
		}


		/**
		 * @brief Handles player-state transitions for provider click tracking.
		 *
		 * A provider click is counted when playback starts and vote tracking is enabled.
		 *
		 * @param station Station associated with the state transition.
		 * @param state New player state.
		 */
		private void on_player_state_changed(Station station, StreamPlayer.State state)
		{
			if (_settings.do_not_vote || state != StreamPlayer.State.PLAYING)
				return;

			_provider.click(station.stationuuid);
			station.clickcount++;
			station.clicktrend++;
		}


		/**
		 * @brief Handles periodic tape-counter events during continuous playback.
		 *
		 * Tracks clicks always (when voting enabled) and votes for starred stations.
		 *
		 * @param station Station that has been playing continuously.
		 */
		private void on_tape_counter(Station station)
		{
			if (_settings.do_not_vote)
				return;

			if (station.starred)
			{
				_provider.vote(station.stationuuid);
				station.votes++;
			}

			_provider.click(station.stationuuid);
			station.clickcount++;
			station.clicktrend++;
		}


		/**
		 * @brief Disconnects coordinator signal handlers and releases resources.
		 */
		public override void dispose()
		{
			if (_player_state_handler_id > 0)
			{
				_events.disconnect(_player_state_handler_id);
				_player_state_handler_id = 0;
			}

			if (_player_tape_handler_id > 0)
			{
				_events.disconnect(_player_tape_handler_id);
				_player_tape_handler_id = 0;
			}

			base.dispose();
		}
	}
}
