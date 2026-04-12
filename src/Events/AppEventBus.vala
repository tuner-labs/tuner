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
	* @brief Typed event hub for application-level cross-component events.
	*/
	public class Events.AppEventBus : GLib.Object
	{
		/** @brief Fired when connectivity state changes. */
		public signal void connectivity_changed_sig (bool is_online);

		/** @brief Fired when shuffle mode changes. */
		public signal void shuffle_mode_sig (bool shuffle);

		/** @brief Emitted when the starred stations change. */
		public signal void starred_stations_changed_sig (Station station);

		/** Signal emitted when the station changes. */
		public signal void station_changed_sig (Station station);

		/** Signal emitted when the player state changes. */
		public signal void state_changed_sig (Station station, Player.State state);

		/** Signal emitted when the title changes. */
		public signal void metadata_changed_sig (Station station, Metadata metadata);

		/** Signal emitted when the volume changes. */
		public signal void volume_changed_sig (double volume);

		/** Signal emitted every ten minutes that a station has been playing continuously. */
		public signal void tape_counter_sig (Station station);

		/** @brief Signal emitted when the shuffle is requested   */
		public signal void shuffle_requested_sig();

	} // AppEventBus

 } // Tuner
