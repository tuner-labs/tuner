/**
 * SPDX-FileCopyrightText: Copyright © 2026 <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file AppEventBus.vala
 */


using Tuner.Models;
using Tuner.Controllers;
using Tuner.Ext;

namespace Tuner {

	/**
	 * @brief Whether Tuner can use the network, as worked out by the ConnectionCoordinator.
	 */
	public enum Events.ConnectionState
	{
		/** @brief No network. */
		OFFLINE,
		/** @brief Network up, but no radio-browser server has answered yet. */
		CONNECTING,
		/** @brief Network up and a radio-browser server has answered. */
		READY;

		/** @brief A short name for log lines. */
		public string label ()
		{
			switch (this)
			{
				case OFFLINE:    return "offline";
				case CONNECTING: return "connecting";
				default:         return "ready";
			}
		}
	}

 
	/**
	* @brief Typed event hub for application-level cross-component events.
	*/
	public class Events.AppEventBus : GLib.Object
	{
		/** @brief Fired when connectivity state changes. */
		public signal void connectivity_changed_sig (bool is_online);

		/**
		 * @brief Fired when the connection state changes: offline, connecting or ready.
		 *
		 * READY means the network is up and a radio-browser server has answered, which is what the
		 * online look and any network work should wait for. See ConnectionCoordinator.
		 */
		public signal void connection_state_changed_sig (Events.ConnectionState state);

		/** @brief Emitted when the starred stations change. */
		public signal void starred_stations_changed_sig (Station station);

		/** Signal emitted when the station changes. */
		public signal void station_changed_sig (Station station);


		/** Signal emitted when the volume changes. */
		public signal void volume_changed_sig (double volume);

/**
	 * @brief Emitted every second while a station is actively playing.
	 *
	 * The payload values are in seconds.
	 */
	public signal void playback_time_tick_sig (Station station, int total_play_seconds, int station_play_seconds);

	/**
	 * @brief Signal emitted every ten minutes while a station has been playing continuously.
	 *
	 * This existing tape-counter milestone event is retained for provider tracking
	 * and jukebox shuffle behavior.
	 */
		public signal void tape_counter_sig (Station station);


		/** @brief Fired when shuffle mode changes. */
		public signal void shuffle_mode_sig (bool shuffle);

		/** @brief Signal emitted when the shuffle is requested   */
		public signal void shuffle_requested_sig();


		// Stream Player signals

		/** Signal emitted when the player state changes. */
		public signal void player_state_changed_sig (Station station, StreamPlayer.State state);	

		//  /** Signal emitted when the title changes. */
		public signal void playback_metadata_changed_sig (Station station, StreamMetadata metadata);

	} // AppEventBus

 } // Tuner
