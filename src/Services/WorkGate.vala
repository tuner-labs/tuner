/**
 * SPDX-FileCopyrightText: Copyright © 2026 <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file WorkGate.vala
 */

namespace Tuner.Services {

	/**
	 * @brief A gate that is closed while some work is in progress, so that others can wait for it.
	 *
	 * A provider closes the gate while it chooses a server, and every query waits at the gate until the
	 * choice has been made, so that nothing is sent before a server is known.
	 *
	 * Used from the main loop only; it is not thread-safe.
	 */
	public class WorkGate : Object
	{
		/** @brief True while the work is in progress */
		public bool closed { get; private set; default = false; }

		private signal void opened_sig ();


		/**
		 * @brief Marks the work as started: from now on wait_until_open() waits.
		 */
		public void close ()
		{
			closed = true;
		} // close


		/**
		 * @brief Marks the work as finished and releases everyone who is waiting.
		 */
		public void open ()
		{
			closed = false;
			opened_sig ();
		} // open


		/**
		 * @brief Waits until the gate is open; returns at once if it already is.
		 */
		public async void wait_until_open ()
		{
			if (!closed)
				return;

			ulong handler = 0;
			handler = opened_sig.connect (() =>
			{
				wait_until_open.callback ();
			});
			yield;
			disconnect (handler);
		} // wait_until_open
	} // WorkGate
} // Tuner.Services
