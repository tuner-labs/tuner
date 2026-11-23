/**
 * SPDX-FileCopyrightText: Copyright © 2026 <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file ServerSelector.vala
 *
 * @brief Chooses which of a set of equivalent API servers to use.
 */

using Gee;

namespace Tuner.Services
{
	/**
	 * @brief The outcome of probing one server.
	 */
	public class ProbeResult : GLib.Object
	{
		/** @brief The server that was probed */
		public string server;

		/** @brief The server answered the probe successfully */
		public bool ok = false;

		/** @brief Milliseconds the successful probe took; negative if it did not succeed */
		public double latency_ms = -1.0;

		/** @brief What the server answered, when the caller can use it (it saves asking again) */
		public InputStream? payload = null;

		/** @brief Creates the record for a server that has not answered yet */
		public ProbeResult(string server)
		{
			this.server = server;
		}
	} // ProbeResult


	/**
	 * @brief Something that can ask one server whether it is working.
	 *
	 * Implemented by the API client, which knows what a healthy answer looks like.
	 */
	public interface ServerProber : GLib.Object
	{
		/**
		 * @brief Asks one server whether it is working, with a single attempt.
		 *
		 * @param server The server to ask
		 * @return How it went. This must not throw, and need not record the result anywhere.
		 */
		public abstract async ProbeResult probe(string server);
	} // ServerProber


	/**
	 * @brief Keeps track of which of a set of equivalent API servers is in use, and chooses a new one.
	 *
	 * The selector does no networking itself. It asks a ServerProber to probe the best-ranked servers
	 * (see ServerPool) at the same time and takes the first that answers, so a dead or slow server
	 * costs nothing while another answers. The outcome of every probe is recorded in the pool, as is
	 * the outcome of the requests the client makes (see record()), so the ranking follows what is
	 * actually happening.
	 *
	 * It knows nothing of any particular API, so any client with mirrored servers can use it.
	 */
	public class ServerSelector : GLib.Object
	{
		/** @brief The servers and their health. The client fills it in and refreshes it. */
		public ServerPool pool { get; private set; }

		/** @brief The server in use */
		public string current { get; private set; }

		/** @brief Whether the last choice found a server that answered its probe */
		public bool proven { get; private set; default = false; }

		private unowned ServerProber _prober;       // Not owned: the prober usually owns the selector
		private int _max_candidates;
		private int _failed_choices = 0;        // Choices in a row where no server answered


		/**
		 * @brief Creates a selector.
		 *
		 * @param prober Probes the servers when a choice is made
		 * @param max_candidates How many of the best-ranked servers are probed when choosing
		 * @param initial The server to use until one has been chosen
		 */
		public ServerSelector(ServerProber prober, int max_candidates, string initial)
		{
			Object();
			pool = new ServerPool();
			current = initial;
			_prober = prober;
			_max_candidates = max_candidates;
		} // ServerSelector


		/**
		 * @brief Records the outcome of a request made to the current server.
		 *
		 * @param ok Whether it was answered successfully
		 * @return True if the server has now failed often enough that it should be retired
		 */
		public bool record(bool ok)
		{
			return pool.record(current, ok);
		} // record


		/**
		 * @brief Stops using the current server for a while (see ServerPool.retire()).
		 *
		 * This does not choose another; call choose() for that.
		 */
		public void retire()
		{
			pool.retire(current);
		} // retire


		/**
		 * @brief Moves on to the next best server without probing it.
		 *
		 * @return false if there is no other server to move to
		 */
		public bool advance()
		{
			var next = pool.best(current);
			if (next == null)
				return false;

			current = next;
			return true;
		} // advance


		/**
		 * @brief Chooses a server by probing the best-ranked ones at the same time.
		 *
		 * The first to answer becomes the current server. If none answers, the best-ranked server
		 * becomes the current server anyway and proven is false.
		 *
		 * @return The winning probe, or null if no server answered
		 */
		public async ProbeResult? choose()
		{
			var candidates = candidates_to_probe();
			if (candidates.is_empty)
			{
				proven = false;
				return null;
			}

			var winner = yield first_to_answer(candidates);

			proven  = winner != null;
			current = proven ? winner.server : candidates[0];
			_failed_choices = proven ? 0 : _failed_choices + 1;

			if (!proven)
				warning(@"ServerSelector - no server answered; using $current\n$(pool.describe())");
			if (Tuner.debug_enabled ())
				debug(@"ServerSelector - chosen server: $current");

			return winner;
		} // choose


		/**
		 * @brief The best-ranked servers to probe, up to the maximum.
		 *
		 * After a choice in which no server answered, every server is probed, so that a few unlucky
		 * ones cannot keep the others from being tried. Servers in a cool-down are used only if
		 * nothing else is left.
		 */
		private Gee.List<string> candidates_to_probe()
		{
			int limit = _failed_choices > 0 ? int.MAX : _max_candidates;
			var candidates = new Gee.ArrayList<string>();
			foreach (var server in pool.ranked())
			{
				if (candidates.size >= limit)
					break;
				if (pool.is_cooling(server) && candidates.size > 0)
					continue;
				candidates.add(server);
			}
			return candidates;
		} // candidates_to_probe


		/**
		 * @brief Probes the servers at the same time and returns the first that answers.
		 *
		 * The probes still running when one answers finish in the background, and still record how
		 * their server did.
		 *
		 * @return The first probe that succeeded, or null if every server failed
		 */
		private async ProbeResult? first_to_answer(Gee.List<string> candidates)
		{
			ProbeResult? winner = null;
			int outstanding = candidates.size;
			bool waiting = false;       // Set once this method has reached its yield
			bool resumed = false;       // A callback can run before the yield is reached

			foreach (var server in candidates)
			{
				_prober.probe.begin(server, (obj, res) =>
				{
					var result = _prober.probe.end(res);
					pool.record(result.server, result.ok, result.ok ? result.latency_ms : -1.0);

					outstanding--;
					if (result.ok && winner == null)
						winner = result;

					if (waiting && !resumed && (winner != null || outstanding == 0))
					{
						resumed = true;
						first_to_answer.callback();
					}
				});
			}

			if (winner == null && outstanding > 0)
			{
				waiting = true;
				yield;
			}
			return winner;
		} // first_to_answer
	} // ServerSelector
}
