/**
 * SPDX-FileCopyrightText: Copyright © 2026 <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file NetworkState.vala
 *
 * @brief Whether the network is usable, and a way to cancel work when it is not.
 */

namespace Tuner.Services
{
	/**
	 * @brief The state of the network connection, as the rest of the app needs to see it.
	 *
	 * Whoever monitors the network reports it with set_online(). Code that makes requests asks
	 * is_offline before sending them, and hands the cancellable to the request so that it is
	 * abandoned the moment the network goes away. This is just the network: whether a
	 * radio-browser server has been proven is the ConnectionCoordinator's business.
	 */
	public class NetworkState : GLib.Object
	{
		/** @brief The network is usable */
		public bool is_online { get; private set; default = false; }

		/** @brief The network is not usable */
		public bool is_offline
		{
			get { return !is_online; }
		}

		/**
		 * @brief Cancelled when the network goes away and reset when it comes back.
		 *
		 * Pass it to requests so they end at once instead of waiting for a time-out.
		 */
		public Cancellable cancellable { get; private set; }

		/**
		 * @brief Emitted when the network goes away or comes back.
		 *
		 * @param is_online The new state
		 */
		public signal void changed (bool is_online);


		construct
		{
			cancellable = new Cancellable();
		}


		/**
		 * @brief Reports the state of the network. Nothing happens if it has not changed.
		 */
		public void set_online (bool online)
		{
			if (online == is_online)
				return;

			if (online)
				cancellable.reset ();
			else
				cancellable.cancel ();

			is_online = online;
			changed (online);
		} // set_online
	} // NetworkState
}
