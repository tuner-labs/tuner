/**
 * SPDX-FileCopyrightText: Copyright © 2020-2024 Louis Brauer <louis@brauer.family>
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file RadioBrowserServers.vala
 *
 * @brief Finds the radio-browser.info API servers
 */

using Gee;
using Tuner.Services;
using Tuner.Services.DataProvider;

namespace Tuner.Providers {

	/**
	 * @brief Finds the radio-browser.info API servers.
	 *
	 * The servers come from the DNS SRV record of radio-browser.info and, failing that, from the API itself
	 * (asked at the round-robin address).
	 */
	public class RadioBrowserServers : Object, ServerFinder
	{
		/** @brief The round-robin API address: it answers for any server, and is the way into the list */
		public const string ROUND_ROBIN = "all.api.radio-browser.info";

		/** @brief The server to fall back on when fewer than two are known */
		public const string RESERVE = "de2.api.radio-browser.info";

		private const string SRV_SERVICE  = "api";
		private const string SRV_PROTOCOL = "tcp";
		private const string SRV_DOMAIN   = "radio-browser.info";
		private const string SERVERS_PATH = "/json/servers";


		/**
		 * @brief Get all radio-browser.info API servers, without blocking the UI
		 *
		 * Gets server list from Radio Browser DNS SRV record,
		 * and failing that, from the API
		 *
		 * @return ArrayList of strings containing the resolved hostnames
		 */
		public async Collection<string> find_servers () throws DataProvider.DataError
		{
			var results = new ArrayList<string>();

			yield add_servers_from_dns (results);

			if (results.is_empty)
				yield add_servers_from_api (results);       // the SRV look-up failed: ask the API itself

			if (Tuner.debug_enabled ())
				debug (@"Results $(results.size)");

			return results;
		} // find_servers


		/**
		 * @brief Adds the servers named by the DNS SRV record of radio-browser.info to results.
		 */
		private async void add_servers_from_dns (ArrayList<string> results)
		{
			try {
				var srv_targets = yield GLib.Resolver.get_default ().lookup_service_async (SRV_SERVICE, SRV_PROTOCOL, SRV_DOMAIN, null);
				foreach (var target in srv_targets) {
					results.add (target.get_hostname ());
				} // foreach
			} catch (GLib.Error e) {
				warning (@"Unable to resolve Radio-Browser SRV records: $(e.message)");
			} // try
		} // add_servers_from_dns


		/**
		 * @brief Adds the servers the API lists, asked at the round-robin address, to results.
		 */
		private async void add_servers_from_api (ArrayList<string> results)
		{
			try {
				uint status_code;

				var uri = RadioBrowser.build_uri_for (ROUND_ROBIN, SERVERS_PATH);
				if (uri == null)
				{
					warning ("find_servers - Invalid URI for servers endpoint");
					return;
				} // if

				var stream = yield HttpClient.GETasync (uri, GLib.Priority.HIGH_IDLE, out status_code);

				if (Tuner.debug_enabled ())
					debug (@"response from $(ROUND_ROBIN)$(SERVERS_PATH): $(status_code)");

				if (status_code == 200 && stream != null)
					read_server_names (stream, results);
			} catch (Error e) {
				warning (@"Failed to parse RBI APIs JSON response: $(e.message)");
			} // try
		} // add_servers_from_api


		/**
		 * @brief Reads the server names out of the /json/servers response and adds them to results.
		 *
		 * @throw DataError if the response is not valid JSON
		 */
		private void read_server_names (InputStream stream, ArrayList<string> results) throws DataProvider.DataError
		{
			Json.Node root_node;

			try {
				var parser = new Json.Parser ();
				parser.load_from_stream (stream);
				root_node = parser.get_root ();
			} catch (Error e) {
				throw new DataProvider.DataError.PARSE_DATA (@"RBI API get servers - unable to parse JSON response: $(e.message)");
			} // try

			if (root_node != null && root_node.get_node_type () == Json.NodeType.ARRAY) {
				root_node.get_array ().foreach_element ((array, index_, element_node) => {
					var object = element_node.get_object ();
					if (object != null) {
						var name = object.get_string_member ("name");
						if (name != null && !results.contains (name)) {
							results.add (name);
						} // if
					} // if
				});
			} // if
		} // read_server_names
	} // RadioBrowserServers
} // Tuner.Providers
