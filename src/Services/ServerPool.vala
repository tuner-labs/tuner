/**
 * SPDX-FileCopyrightText: Copyright © 2026 <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file ServerPool.vala
 *
 * @brief Tracks the health of the API servers and ranks them.
 */

using Gee;

namespace Tuner.Services
{
	/**
	 * @brief The set of API servers, with a health record for each.
	 *
	 * This class does no networking. The provider reports the outcome of every request
	 * (and of its probes) with record(), and asks which server to use next with ranked()
	 * or best().
	 *
	 * Health is an exponentially weighted success rate (recent results count most) and an
	 * exponentially weighted response time. A server whose success rate drops too low is
	 * retired: it is skipped for a cool-down period, after which it is given another chance.
	 * Servers that have not been tried yet look perfect, so each gets tried.
	 *
	 * Ties are broken randomly, so load spreads across equally good servers.
	 */
	public class ServerPool : GLib.Object
	{
		private const double EWMA_ALPHA       = 0.3;     // weight of the newest result
		private const uint   MIN_SAMPLES      = 8u;      // results needed before a server can be judged
		private const double MIN_SUCCESS_RATE = 0.4;     // below this a server is retired
		private const double MAX_LATENCY_MS   = 5000.0;  // latency above this counts the same
		private const double LATENCY_WEIGHT   = 0.2;     // most a slow server can lose in score
		private const int64  COOLDOWN_US      = 300000000LL;   // 5 minutes

		private class Health : GLib.Object
		{
			public double rate = 1.0;          // success rate, 0..1
			public double latency_ms = 0.0;    // 0 = not measured yet
			public uint   samples = 0u;
			public int64  bad_until = 0LL;     // monotonic time (us) the cool-down ends; 0 = not retired
		}

		private ArrayList<string> _servers = new ArrayList<string>();
		private HashMap<string, Health> _health = new HashMap<string, Health>();


		/** @brief Number of servers in the pool. */
		public int size
		{
			get { return _servers.size; }
		}


		/**
		 * @brief Replace the servers. Health records of servers that stay are kept.
		 */
		public void set_servers(Collection<string> names)
		{
			_servers.clear();
			add_servers(names);
		} // set_servers


		/**
		 * @brief Add servers that are not in the pool yet.
		 *
		 * @return How many were new.
		 */
		public int add_servers(Collection<string> names)
		{
			int added = 0;
			foreach (var raw in names)
			{
				var name = raw.strip();
				if (name == "" || _servers.contains(name))
					continue;

				_servers.add(name);
				if (!_health.has_key(name))
					_health[name] = new Health();
				added++;
			}
			return added;
		} // add_servers


		/**
		 * @brief Whether the pool contains the server.
		 */
		public bool contains(string server)
		{
			return _servers.contains(server);
		} // contains


		/**
		 * @brief Record the outcome of one request or probe.
		 *
		 * @param server The server that was asked.
		 * @param ok Whether it answered successfully.
		 * @param latency_ms Time the successful request took, or negative if not measured.
		 * @return True if this server has now failed often enough that it should be retired.
		 */
		public bool record(string server, bool ok, double latency_ms = -1.0)
		{
			var health = _health[server];
			if (health == null)
				return false;

			health.samples++;
			health.rate = health.rate * (1.0 - EWMA_ALPHA) + (ok ? 1.0 : 0.0) * EWMA_ALPHA;

			if (ok && latency_ms >= 0.0)
			{
				health.latency_ms = health.latency_ms == 0.0
					? latency_ms
					: health.latency_ms * (1.0 - EWMA_ALPHA) + latency_ms * EWMA_ALPHA;
			}

			return !ok && health.samples >= MIN_SAMPLES && health.rate < MIN_SUCCESS_RATE;
		} // record


		/**
		 * @brief Skip the server for the cool-down period.
		 */
		public void retire(string server)
		{
			var health = _health[server];
			if (health != null)
				health.bad_until = GLib.get_monotonic_time() + COOLDOWN_US;
		} // retire


		/**
		 * @brief Whether the server is in its cool-down.
		 */
		public bool is_cooling(string server)
		{
			var health = _health[server];
			return health != null && health.bad_until > GLib.get_monotonic_time();
		} // is_cooling


		/**
		 * @brief All servers, best first.
		 *
		 * Servers that are not cooling down come first, ordered by score; cooling servers
		 * follow, the one that comes back soonest first. Equal servers are in random order.
		 */
		public ArrayList<string> ranked()
		{
			var now = GLib.get_monotonic_time();

			// Start from a random rotation so that ties are broken at random
			var remaining = new ArrayList<string>();
			if (_servers.size > 0)
			{
				int start = Random.int_range(0, _servers.size);
				for (int i = 0; i < _servers.size; i++)
					remaining.add(_servers[(start + i) % _servers.size]);
			}

			var result = new ArrayList<string>();
			while (!remaining.is_empty)
			{
				string pick = remaining[0];
				foreach (var candidate in remaining)
				{
					if (better(candidate, pick, now))
						pick = candidate;
				}
				result.add(pick);
				remaining.remove(pick);
			}
			return result;
		} // ranked


		/**
		 * @brief The best server that is not cooling down and is not `exclude`.
		 *
		 * @return The server, or null if there is none.
		 */
		public string? best(string? exclude = null)
		{
			foreach (var server in ranked())
			{
				if (server != exclude && !is_cooling(server))
					return server;
			}
			return null;
		} // best


		/**
		 * @brief One line per server, for the log.
		 */
		public string describe()
		{
			var text = new StringBuilder();
			foreach (var server in ranked())
			{
				var health = _health[server];
				text.append(@"$(server): $((int) (health.rate * 100))% ok, $((int) health.latency_ms) ms, $(health.samples) results$(is_cooling(server) ? ", cooling down" : "")\n");
			}
			return text.str;
		} // describe


		/**
		 * @brief Whether server `a` should be tried before server `b`.
		 */
		private bool better(string a, string b, int64 now)
		{
			var ha = _health[a];
			var hb = _health[b];

			bool cool_a = ha.bad_until > now;
			bool cool_b = hb.bad_until > now;

			if (cool_a != cool_b)
				return !cool_a;                       // not cooling beats cooling

			if (cool_a)
				return ha.bad_until < hb.bad_until;   // both cooling: the one back sooner

			return score(ha) > score(hb);
		} // better


		private double score(Health health)
		{
			double latency = health.latency_ms > MAX_LATENCY_MS ? MAX_LATENCY_MS : health.latency_ms;
			return health.rate - (latency / MAX_LATENCY_MS) * LATENCY_WEIGHT;
		} // score
	} // ServerPool
}
