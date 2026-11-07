/**
 * SPDX-FileCopyrightText: Copyright © 2020-2024 Louis Brauer <louis@brauer.family>
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file ServerDirectory.vala
 *
 * @brief Keeps the pool of API servers stocked
 */

using Gee;
using Tuner.Services.DataProvider;

namespace Tuner.Services {

	/**
	 * @brief Something that can find out which servers an API is served from.
	 *
	 * Implemented for each API: the DNS record, directory request or list in a file that names its servers.
	 */
	public interface ServerFinder : GLib.Object
	{
		/**
		 * @brief Finds the servers.
		 *
		 * @return The server names; empty if none could be found
		 * @throw DataError if the look-up failed in a way worth reporting
		 */
		public abstract async Collection<string> find_servers () throws DataProvider.DataError;
	} // ServerFinder


	/**
	 * @brief Keeps a pool of API servers stocked, and refreshed from time to time.
	 *
	 * The servers are the ones given up front (for example on the command line), or else those a
	 * ServerFinder finds. A reserve list is added when fewer than two servers are known. Servers that are
	 * given up front are used as they are and never refreshed.
	 *
	 * This class fills the pool; ServerSelector chooses from it.
	 */
	public class ServerDirectory : Object
	{
		private const int64 REFRESH_INTERVAL_US = 600000000LL;     // list refreshed at most every 10 minutes
		private const int MIN_SERVERS           = 2;               // fewer than this and the reserve list is added

		private ServerPool _pool;
		private NetworkState _network;
		private ServerFinder _finder;
		private string? _fixed_servers;       // Colon-separated servers given up front, or null
		private string? _reserve_servers;     // Colon-separated servers to add when too few are known, or null
		private int64 _last_refresh = 0LL;


		/**
		 * @param pool The pool to fill
		 * @param network Network state: nothing is asked while offline
		 * @param finder Finds the servers when they are not given up front
		 * @param fixed_servers Colon-separated servers to use instead of looking them up, or null
		 * @param reserve_servers Colon-separated servers to add when fewer than two are known, or null
		 */
		public ServerDirectory (ServerPool pool, NetworkState network, ServerFinder finder,
		                        string? fixed_servers, string? reserve_servers)
		{
			Object ();
			_pool            = pool;
			_network         = network;
			_finder          = finder;
			_fixed_servers   = fixed_servers;
			_reserve_servers = reserve_servers;
		} // ServerDirectory


		/**
		 * @brief Fills the pool: with the servers given up front, or else with those found.
		 *
		 * @throw DataError if the servers had to be looked up and the look-up failed
		 */
		public async void load () throws DataProvider.DataError
		{
			if (_fixed_servers != null)
			{
				_pool.set_servers (new ArrayList<string>.wrap (_fixed_servers.split (":")));
				return;
			}

			_pool.set_servers (yield find ());
			_last_refresh = GLib.get_monotonic_time ();
			add_reserve_servers ();
		} // load


		/**
		 * @brief Asks for the current server list, at most every REFRESH_INTERVAL_US.
		 *
		 * New servers are added to the pool; known ones keep their health record.
		 * Does nothing when the servers were given up front.
		 */
		public async void refresh_if_due ()
		{
			if (_fixed_servers != null || _network.is_offline)
				return;

			var now = GLib.get_monotonic_time ();
			if (_last_refresh != 0LL && now - _last_refresh < REFRESH_INTERVAL_US)
				return;
			_last_refresh = now;

			try {
				var added = _pool.add_servers (yield find ());
				if (Tuner.debug_enabled ())
					debug (@"Server list refreshed, $added new");
			} catch (DataError e) {
				warning (@"Unable to refresh the server list: $(e.message)");
			}
			add_reserve_servers ();
		} // refresh_if_due


		/**
		 * @brief Asks the finder, unless the network is down.
		 */
		private async Collection<string> find () throws DataProvider.DataError
		{
			if (_network.is_offline)
				return new ArrayList<string>();

			return yield _finder.find_servers ();
		} // find


		/**
		 * @brief Add the reserve servers when fewer than two servers are known.
		 */
		private void add_reserve_servers ()
		{
			if (_fixed_servers != null || _reserve_servers == null || _pool.size >= MIN_SERVERS)
				return;

			_pool.add_servers (new ArrayList<string>.wrap (_reserve_servers.split (":")));
			debug ("Fewer than two servers known, reserve server added");
		} // add_reserve_servers
	} // ServerDirectory
} // Tuner.Services
