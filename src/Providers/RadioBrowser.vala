/**
 * SPDX-FileCopyrightText: Copyright © 2020-2024 Louis Brauer <louis@brauer.family>
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file RadioBrowser.vala
 *
 * @brief Interface to radio-browser.info API and servers
 * 
 */

using Gee;
using Tuner.Models;
using Tuner.Services;
using Tuner.Services.DataProvider;

/**
 * @namespace Tuner.RadioBrowser
 *
 * @brief DataProvider implementation for radio-browser.info API and servers
 *
 * This namespace provides functionality to interact with the radio-browser.info API.
 * It includes features for:
 * - Retrieving radio station metadata JSON
 * - Executing searches and retrieving radio station metadata JSON
 * - Reporting back user interactions (voting, listen tracking)
 * - Tag and other metadata retrieval
 * - API Server discovery and connection handling from DNS and from round-robin API server
 */
namespace Tuner.Providers {

    private const string SRV_SERVICE    = "api";
    private const string SRV_PROTOCOL   = "tcp";
    private const string SRV_DOMAIN     = "radio-browser.info";

    /*
        RadioBrowser API this provider is written against
        --------------------------------------------------
        Documentation : https://api.radio-browser.info/ (the old www.radio-browser.info API is deprecated)
        Protocol      : JSON over HTTPS ("preferably HTTPS" per the docs), paths under /json/
        Wire version  : /json/stats reports "supported_version" - this code expects RBI_API_SUPPORTED_VERSION
        Spec reference: OpenAPI listing at https://apis.io/apis/radio-browser/radio-browser-stations-api/
                        shows info.version 0.7.44 (third party copy - check against a live server's
                        "software_version" in /json/stats). Last reviewed against it: 2026-10-21.
        Rules followed: speaking User-Agent (app/version), server list from DNS SRV (fallback /json/servers),
                        random server order, retry a failed request on the next server, /json/url on each play,
                        use uuids and countrycode (not the legacy id/country fields) for lookups, hidebroken=true.
    */
    private const int    RBI_API_SUPPORTED_VERSION = 1;
    private const string RBI_SCHEME     = "https";
    private const string RBI_CACHE_BUSTER = "nocache";   // query parameter, value differs on every request

    // A catalogue query is tried this many times. radio-browser.info often drops the first connection with
    // "connection reset", and the server list can hold a single server, so a retry may go to the same server.
    private const int  MAX_QUERY_ATTEMPTS   = 3;
    private const uint QUERY_RETRY_DELAY_MS = 300u;

    private const string RBI_ALL_API    = "all.api.radio-browser.info";    // Round-robin API address
    private const string RBI_STATS      = "/json/stats";
    private const string RBI_SERVERS    = "/json/servers";

    // RB Queries
    private const string RBI_STATION    = "/json/url/";    // + stationuuid
    private const string RBI_SEARCH     = "/json/stations/search";
    private const string RBI_VOTE       = "/json/vote/";   // + stationuuid
    private const string RBI_UUID       = "/json/stations/byuuid";
    private const string RBI_URL        = "/json/stations/byurl";
    private const string RBI_TAGS       = "/json/tags";
    


    /**
     * A data provider implementation for the Radio Browser API.
     * 
     * RadioBrowser class implements the DataProvider.API interface to fetch
     * radio station data from the Radio Browser service.
     * 
     * See https://api.radio-browser.info/ for API details (and the API version note at the top of this file).
     */
    public class RadioBrowser : Object, API 
    {
        private const int DEGRADE_CAPITAL = 100;
        private const int DEGRADE_COST = 7;

        private string? _optional_servers;
        private const int    PROBE_CANDIDATES = 3;           // servers probed when choosing
        private const int    PROBES_PER_SERVER = 2;          // stats requests per candidate
        private const int64  REFRESH_INTERVAL_US = 600000000LL;   // list refreshed at most every 10 minutes
        private const string FALLBACK_SERVERS = "de2.api.radio-browser.info";   // used only when fewer than two are known

        private ServerPool _pool = new ServerPool();
        private int64 _last_refresh = 0LL;
        private string _current_server = RBI_ALL_API;
        private int _degrade = DEGRADE_CAPITAL;
        private int _available_stations = 1000;     // default guess
        private int _available_tags = 1000;     // default guess
        private int _api_supported_version = 0;          // From /json/stats "supported_version", 0 = unknown
        private string _api_software_version = "unknown"; // From /json/stats "software_version"


        /**
         * @brief Provider description: name, current server and API version.
         */
        public string name()
        {
            return @"RadioBrowser 2.0\n\nServer: $_current_server\nAPI version: $_api_software_version (wire v$_api_supported_version)"; 
        } // name


        public Status status { get; protected set; }

        public DataError? last_data_error { get; set; }

		/**
		 * @brief Station count reported by the server's stats.
		 */
		public int available_stations()
		{
			return _available_stations;
		} // available_stations

		/**
		 * @brief Tag count reported by the server's stats.
		 */
		public int available_tags()
		{
			return _available_tags;
		} // available_tags


        /**
        * @brief Constructor for RadioBrowser Client
        *
        * @throw DataError if unable to initialize the client
        */
		public RadioBrowser(string? optional_servers )
		{
			Object( );
			_optional_servers = optional_servers;
			status           = NOT_AVAILABLE;
		} // RadioBrowser


        /**
         * @brief Cache-busting query parameter that is different for every request.
         *
         * The value is the time in milliseconds, forced to rise by at least one per call, so it
         * is unique within a run and across runs. radio-browser.info ignores parameters it does
         * not know.
         *
         * The `offset` parameter is NOT used for this: on a search it is the paging position, and
         * a rising offset would skip the top of Popular and Trending. It is only safe to rise on
         * random searches, where StationSet already does that.
         */
        private static string cache_buster()
        {
            int64 now = GLib.get_real_time() / 1000;
            if (now <= _cache_serial)
                now = _cache_serial + 1;
            _cache_serial = now;
            return @"$(RBI_CACHE_BUSTER)=$now";
        } // cache_buster

        private static int64 _cache_serial = 0;


        /**
         * @brief Builds a Glib Uri from path and query
         *
         * Uses Glib Uri Parse with encoding to correctly check and encode the query
         *
         * @return the Uri if successful
         */
        private Uri? build_uri(string path, string query = "")
        {          
            try {
                // Every request gets a cache-busting parameter: caches and proxies on the way to
                // radio-browser.info otherwise answer repeat requests (random picks, failed or stale
                // responses, even clicks) without the server seeing them.
                var busted = query == "" ? cache_buster() : @"$query&$(cache_buster())";
                return Uri.parse(@"$(RBI_SCHEME)://$_current_server$path?$busted",UriFlags.ENCODED);
            } catch (UriError e)
            {
                warning(@"Server: $_current_server  Path: $path  Query: $query  Error: $(e.message)");
            }
            return null;
        } // build_uri


        /**
         * @brief Initialize the DataProvider implementation
         *
         * @return true if initialization successful
        */
        public bool initialize()
        {
            if ( app().is_offline ) return false;
            
            if (_optional_servers != null) 
            // Run time server parameter was passed in
            {
                _pool.set_servers(new Gee.ArrayList<string>.wrap(_optional_servers.split(":")));
            } else 
            // Identify servers from DNS or API
            {
                try {
                    _pool.set_servers(get_srv_api_servers());
                    _last_refresh = GLib.get_monotonic_time();
                    add_fallback_servers();
                } catch (DataError e) {
                    last_data_error = new DataError.NO_CONNECTION(@"Failed to retrieve API servers: $(e.message)");
                    status = NO_SERVER_LIST;
                    return false;
                }
            } // if

			if (_pool.size == 0)
			{
				last_data_error = new DataError.NO_CONNECTION("Unable to resolve API servers for radio-browser.info");
				status          = NO_SERVERS_PRESENTED;
				return false;
			} // if

            choose_server();
            status = OK;
            clear_last_error();
            stats();
            return true;
        } // initialize


        /**
         * @brief Track a station listen event
         *
         * Fire-and-forget: the request is sent in the background and this returns at once,
         * so a slow or resetting server never stalls the caller (this runs on every play).
         *
         * @param stationuuid UUID of the station being listened to
         */
        public void click(string stationuuid)
        {
            send_station_event.begin(RBI_STATION, stationuuid, "listening");
        } // click


        /**
         * @brief Vote for a station
         *
         * Fire-and-forget, like `click()`.
         *
         * @param stationuuid UUID of the station being voted for
         */
        public void vote(string stationuuid)
        {
            send_station_event.begin(RBI_VOTE, stationuuid, "vote");
        } // vote


        /**
         * @brief Send a per-station event (/json/url click or /json/vote) without blocking.
         *
         * @param path Endpoint prefix, the station uuid is appended
         * @param stationuuid UUID of the station
         * @param event_name Name used in log messages
         */
        private async void send_station_event(string path, string stationuuid, string event_name)
        {
            if (Tuner.debug_enabled ())
                debug(@"sending $(event_name) event for station $(stationuuid)");

            var uri = build_uri(path + stationuuid);
            if (uri == null)
            {
                warning(@"$(event_name) - Invalid URI for station $(stationuuid)");
                return;
            }

            uint status_code;
            yield HttpClient.GETasync(uri, Priority.LOW, out status_code);

            if (Tuner.debug_enabled ())
                debug(@"$(event_name) response: $(status_code)");
        } // send_station_event


        /**
         * @brief Get all available tags
         *
         * @return ArrayList of Tag objects
         * @throw DataError if unable to retrieve or parse tag data
         */
         public Set<Tag> get_tags(int offset, int limit) throws DataError {
            Json.Node root_node;
            try {
                uint status_code;
                var query = "";
                if (offset > 0) query = @"offset=$offset";
                if (limit > 0) query = @"$query&limit=$limit";

				var uri    = build_uri(RBI_TAGS, query);
                if (uri == null)
                {
                    warning(@"get_tags - Invalid URI for query: $(query)");
                    return new HashSet<Tag>();
                } // if
				var stream = HttpClient.GET(uri, out status_code);

                if ( status_code != 0 && stream != null)
                {
                    try {
                        var parser =  new Json.Parser();
                        parser.load_from_stream(stream);
                        root_node = parser.get_root();
                    } catch (Error e) {
                        throw new DataError.PARSE_DATA(@"unable to parse JSON response: $(e.message)");
                    }
                    var root_array = root_node.get_array();
                    var tags = jarray_to_tags(root_array);
                    return tags;
                } // if

            } catch (GLib.Error e) {
                debug("cannot get_tags()");
            } // try
            return new HashSet<Tag>();
        } // get_tags


        /**
         * @brief Get a station or stations by UUID
         *
         * @param uuids comma separated lists of the stations to retrieve
         * @return Station object if found, null otherwise
         * @throw DataError if unable to retrieve or parse station data
         */
         public Set<Station> by_uuid(string uuid) throws DataError {
            if ( app().is_offline || safestrip(uuid).length == 0 ) return new HashSet<Station>();
            var result = station_query(RBI_UUID,@"uuids=$uuid");
            return result;
        } // by_uuid


        /**
         * @brief Get a station or stations by UUIDs
         *
         * @param a collection of uuids of the stations to retrieve
         * @return Station object if found, null otherwise
         * @throw DataError if unable to retrieve or parse station data
         */
        public Set<Station> by_uuids(Collection<string> uuids) throws DataError {
            StringBuilder sb = new StringBuilder();
            foreach ( var uuid in uuids) { sb.append(uuid).append(","); }
            return by_uuid(sb.str);
        } // by_uuid


        /**
            Not implemented
        */
        public Set<Station> by_url(string url) throws DataError {
            if ( app().is_offline || safestrip(url).length == 0 ) return new HashSet<Station>();
            var result = station_query(RBI_URL,@"url=$(encode_text(url))");
            return result;
        } // by_url


        /**
        * @brief Search for stations based on given parameters
        *
        * @param params Search parameters
        * @param rowcount Maximum number of results to return
        * @param offset Offset for pagination
        * @return ArrayList of Station objects matching the search criteria
        * @throw DataError if unable to retrieve or parse station data
        */
		public Set<Station> search(SearchParams params, uint rowcount, uint offset = 0) throws DataError
		{
			// by uuids
			if (params.uuids != null)
			{
				return by_uuids(params.uuids);
			}

            // OR

			// by text or tags
			var query = get_search_query_params(params,rowcount, offset);

			debug(@"Search: $(query)");
			return station_query(RBI_SEARCH, query);
		} // search


        /**
        * @brief Search for stations based on given parameters
        *
        * @param params Search parameters
        * @param rowcount Maximum number of results to return
        * @param offset Offset for pagination
        * @param priority Priority of the HTTP request; GLib.Priority.LOW for background loads
        * @return ArrayList of Station objects matching the search criteria
        * @throw DataError if unable to retrieve or parse station data
        */
		public async Set<Station> search_async(SearchParams params, uint rowcount, uint offset = 0, int priority = GLib.Priority.HIGH_IDLE) throws DataError
		{
			// by uuids
			if (params.uuids != null)
			{
				return by_uuids(params.uuids);
			}

			// OR

			// by text or tags
			var query = get_search_query_params(params, rowcount, offset);

            if (Tuner.debug_enabled ())
                debug(@"Search: $(query)");
            return  yield station_query_async(RBI_SEARCH, query, priority);
        } // search



        /*  ---------------------------------------------------------------
            Private
            ---------------------------------------------------------------*/

        /**
         * @brief Log a warning when a catalogue query that should return stations returns none.
         *
         * A failed or odd response otherwise looks exactly like "no stations", and the category
         * stays empty with nothing in the log. Text and tag searches can legitimately find nothing,
         * so those are left alone.
         *
         * @return The stations, unchanged.
         */
        private Set<Station> warn_if_empty(Set<Station> stations, Uri uri)
        {
            var query = uri.get_query () ?? "";
            if (stations.size == 0 && !query.contains ("name=") && !query.contains ("tagList="))
                warning(@"'radio-browser.info' returned no stations for url: $(uri.to_string()) [server=$(_current_server)]");
            return stations;
        } // warn_if_empty


        /**
         * @brief Whether a failed response is worth retrying on another server.
         *
         * No response at all (0) or a server-side error (5xx). Client errors (4xx) would fail everywhere.
         */
        private static bool is_retryable(uint status_code)
        {
            return status_code == 0 || status_code >= 500;
        } // is_retryable


        /**
         * @brief Move on to the next server in the discovered list.
         *
         * The docs say: "If a request fails just retry the request with the next entry in the list".
         *
         * @return false if there is no other server to move to.
         */
        private bool switch_to_next_server()
        {
            var next = _pool.best(_current_server);
            if (next == null)
                return false;

            _current_server = next;
            debug(@"RadioBrowser Client - retrying on next server: $_current_server");
            return true;
        } // switch_to_next_server


        /**
         * @brief Get all available tags
         *
         * @return ArrayList of Tag objects
         * @throw DataError if unable to retrieve or parse tag data
         */
        private void choose_server()
        {
            string? chosen = null;
            int chosen_ok = -1;
            int tried = 0;

            foreach (var server in _pool.ranked())
            /* Best servers first; probe a few and take the first that answers every probe */
            {
                if (tried >= PROBE_CANDIDATES)
                    break;
                if (_pool.is_cooling(server) && tried > 0)
                    continue;           // cooling servers only if nothing else is left
                tried++;

                int ok = 0;
                for (int probe = 0; probe < PROBES_PER_SERVER; probe++)
                {
                    uint status = 0;
                    var saved = _current_server;
                    _current_server = server;
                    var uri = build_uri(RBI_STATS);
                    _current_server = saved;
                    if (uri == null)
                    {
                        debug(@"Server - bad Uri from $server");
                        break;
                    }

                    var began = GLib.get_monotonic_time();
                    HttpClient.GET(uri, out status);
                    var ms = (GLib.get_monotonic_time() - began) / 1000.0;

                    _pool.record(server, status == 200, status == 200 ? ms : -1.0);
                    if (status == 200)
                        ok++;
                }

                if (ok > chosen_ok)
                {
                    chosen = server;
                    chosen_ok = ok;
                }
                if (ok == PROBES_PER_SERVER)
                    break;
            }

            if (chosen != null)
                _current_server = chosen;

            if (chosen_ok < PROBES_PER_SERVER)
                warning(@"RadioBrowser Client - no server answered every probe; using $_current_server\n$(_pool.describe())");
            debug(@"RadioBrowser Client - Chosen radio-browser.info server: $_current_server");
        } // choose_server
    

        /**
         * @brief Manages tracking server degradation and new server selection
         *
         * Tracks degraded server responses and at a certain level will choose 
         * a new server if possible 
         */
        private void degrade(bool degraded = true )
        {
            var unhealthy = _pool.record(_current_server, !degraded);

            if ( !degraded ) 
            // Track nominal result
            {
                _degrade += ((_degrade > DEGRADE_CAPITAL) ? 0 : 1);
            }
            else
            // Degraded result
            {
                warning(@"RadioBrowser degrading server: $_current_server");
                _degrade -= DEGRADE_COST;
                if ( _degrade < 0 || unhealthy ) 
                // This server is out of score, or its recent results are mostly failures
                {
                    retire_current_server();
                } // if
            } // if
        } // degrade


        /**
         * @brief Stop using the current server for a while and choose another.
         *
         * The server is put into a cool-down, the list of servers is refreshed if it has not
         * been recently, and a new server is chosen by probing.
         */
        private void retire_current_server()
        {
            warning(@"RadioBrowser retiring server $_current_server");
            _pool.retire(_current_server);
            refresh_servers_if_due();
            choose_server();
            _degrade = DEGRADE_CAPITAL;
        } // retire_current_server


        /**
         * @brief Ask DNS / the API for the current server list, at most every REFRESH_INTERVAL_US.
         *
         * New servers are added to the pool; known ones keep their health record.
         * Does nothing when the servers were given on the command line.
         */
        private void refresh_servers_if_due()
        {
            if (_optional_servers != null || app().is_offline)
                return;

            var now = GLib.get_monotonic_time();
            if (_last_refresh != 0LL && now - _last_refresh < REFRESH_INTERVAL_US)
                return;
            _last_refresh = now;

            var saved = _current_server;
            _current_server = RBI_ALL_API;      // the round-robin name, in case the current server is the problem
            try {
                var added = _pool.add_servers(get_srv_api_servers());
                debug(@"RadioBrowser Client - server list refreshed, $added new");
            } catch (DataError e) {
                warning(@"RadioBrowser Client - unable to refresh server list: $(e.message)");
            }
            _current_server = saved;
            add_fallback_servers();
        } // refresh_servers_if_due


        /**
         * @brief Add the reserve server when fewer than two servers are known.
         */
        private void add_fallback_servers()
        {
            if (_optional_servers != null || _pool.size >= 2)
                return;

            _pool.add_servers(new Gee.ArrayList<string>.wrap(FALLBACK_SERVERS.split(":")));
            debug("RadioBrowser Client - fewer than two servers known, reserve server added");
        } // add_fallback_servers

    
        /**
         * @brief Retrieve server stats
         *
         */
        private void stats() 
         {
            uint status_code;
            Json.Node root_node;

            var uri = build_uri(RBI_STATS);
            if (uri == null)
            {
                warning("stats - Invalid URI");
                return;
            } // if

            var stream = HttpClient.GET(uri, out status_code);

            if ( status_code != 0 && stream != null)
            {
                try {
                    var parser = new Json.Parser();
                    parser.load_from_stream(stream, null);
                    root_node = parser.get_root();
                    Json.Object json_object = root_node.get_object();
                    _available_stations = (int)json_object.get_int_member("stations");
                    _available_tags = (int)json_object.get_int_member("tags");

                    if (json_object.has_member("supported_version"))
                        _api_supported_version = (int)json_object.get_int_member("supported_version");
                    if (json_object.has_member("software_version"))
                        _api_software_version = json_object.get_string_member("software_version");
                    if (_api_supported_version != 0 && _api_supported_version != RBI_API_SUPPORTED_VERSION)
                        warning(@"RadioBrowser server $_current_server reports API wire version $_api_supported_version, this code expects $RBI_API_SUPPORTED_VERSION");
                    debug(@"RadioBrowser API software version $_api_software_version, wire version $_api_supported_version");

                } catch (Error e) {
                    warning(@"Could not get server stats: $(e.message)");
                } // try
            } // if
            debug(@"response: $(status_code) - Stations: $(_available_stations) Tags: $(_available_tags)");
        } // stats

            
        /**
         * @brief Get stations by querying the API
         *
         * @param query the API query
         * @return ArrayList of Station objects
         * @throw DataError if unable to retrieve or parse station data
         */
        private Set<Station> station_query(string path, string query) throws DataProvider.DataError {

            if (Tuner.debug_enabled ())
                debug(@"station_query - $(path) $(query)");

            for (int attempt = 1; attempt <= MAX_QUERY_ATTEMPTS; attempt++)
            // Later attempts go to a different server when there is one, otherwise to the same server again
            {
                uint status_code;
                var uri = build_uri(path, query);
                if (uri == null)
                {
                    warning(@"station_query - Invalid URI for path $(path) query $(query)");
                    degrade();
                    return new HashSet<Station>();
                } // if

                if (Tuner.debug_enabled ())
                    debug(@"station_query - $(uri.to_string())");

                var stream =  HttpClient.GET(uri,  out status_code);

                if (status_code == 200 && stream != null)
                {
                    degrade(false);
                    try
                    {
                        return warn_if_empty(parse_json_response(stream), uri);
                    } catch (Error e)
                    {
                        warning(@"Could not read the station list from 'radio-browser.info': $(e.message) for url: $(uri.to_string())");
                    }
                    return new HashSet<Station>();
                } // if

                warning(@"Response from 'radio-browser.info': $(status_code) for url: $(uri.to_string()) [server=$(_current_server) degrade=$(_degrade) offline=$(app().is_offline)]");
                var failed_server = _current_server;
                degrade();      // May already have chosen a new server

                if (attempt < MAX_QUERY_ATTEMPTS && is_retryable(status_code))
                {
                    if (_current_server == failed_server)
                        switch_to_next_server();    // false when this is the only server: try it again
                    continue;
                }
                break;
            } // for
            return new HashSet<Station>();
		} // station_query


        /**
        * @brief Get stations by querying the API
        *
        * @param query the API query
        * @return ArrayList of Station objects
        * @throw DataError if unable to retrieve or parse station data
        */
		private async Set<Station> station_query_async(string path, string query, int priority = GLib.Priority.HIGH_IDLE) throws DataError
		{
			if (Tuner.debug_enabled ())
				debug(@"station_query_async - $(path) $(query)");

			for (int attempt = 1; attempt <= MAX_QUERY_ATTEMPTS; attempt++)
			// Later attempts go to a different server when there is one, otherwise to the same server again
			{
				uint status_code;
				var  uri = build_uri(path, query);
				if (uri == null)
				{
					warning(@"station_query_async - Invalid URI for path $(path) query $(query)");
					degrade();
					return new HashSet<Station>();
				} // if

				if (Tuner.debug_enabled ())
					debug(@"station_query_async - $(uri.to_string())");

				var stream =  yield HttpClient.GETasync(uri,  priority, out status_code);

				if (status_code == 200 && stream != null)
				{
					degrade(false);
					try
					{
						return warn_if_empty(parse_json_response(stream), uri);
					} catch (Error e)
					{
						warning(@"Could not read the station list from 'radio-browser.info': $(e.message) for url: $(uri.to_string())");
					} // try
					return new HashSet<Station>();
				} // if

				warning(@"Response from 'radio-browser.info': $(status_code) for url: $(uri.to_string()) [server=$(_current_server) degrade=$(_degrade) offline=$(app().is_offline)]");
				var failed_server = _current_server;
				degrade();      // May already have chosen a new server

				if (attempt < MAX_QUERY_ATTEMPTS && is_retryable(status_code))
				{
					if (_current_server == failed_server)
						switch_to_next_server();    // false when this is the only server: try it again

					Timeout.add(QUERY_RETRY_DELAY_MS * (uint) attempt, station_query_async.callback);   // brief pause, without blocking the UI
					yield;
					continue;
				}
				break;
			} // for
			return new HashSet<Station>();
		} // station_query_async



        /**
         * Generates query parameters string for radio-browser API search requests.
         *
         * @param params    SearchParams object containing search criteria
         * @param rowcount  Maximum number of results to return
         * @param offset    Starting position in the result set
         *
         * @return String containing formatted query parameters
         */
        private string get_search_query_params(DataProvider.SearchParams params, uint rowcount, uint offset)
        {
            // by text or tags
            // hidebroken: the API default includes stations whose last health check failed
            var query = @"limit=$rowcount&order=$(params.order)&offset=$offset&hidebroken=true";

            if (params.text != "") {
                query += @"&name=$(encode_text(params.text))";  // Encode text for ampersands etc
            } // if

            if (params.countrycode.length > 0) {
                query += @"&countrycode=$(params.countrycode)";
            } // if

            if (params.order != DataProvider.SortOrder.RANDOM) {
                // random and reverse doesn't make sense
                query += @"&reverse=$(params.reverse)";
            } // if

            // Put tags last
            if (params.tags.size > 0) {
                string tag_list = params.tags.to_array()[0];
                if (params.tags.size > 1) {
                    tag_list = string.joinv(",", params.tags.to_array());
                }
                query += @"&tagExact=false&tagList=$(encode_text(tag_list))"; // Encode text for ampersands etc
            } // if

            return query;
        } // get_search_query_params


        /**
         * Parses JSON response from Radio Browser API into a set of stations.
         *
         * @param stream The input stream containing JSON data to be parsed
         *
         * @return Set<Station> A set of Station objects parsed from the JSON
         *
         * @throws Error If there is an error parsing the JSON or processing the data
         */
         private Set<Station> parse_json_response(InputStream stream) throws Error
         {
             var parser = new Json.Parser.immutable_new ();
             parser.load_from_stream(stream, null);
             var root_node = parser.get_root();
             var root_array = root_node.get_array();
             return jarray_to_stations(root_array);
         } // parse_json_response


        /**
        * @brief Marshals JSON array data into an array of Station
        *
        * Not knowing what the produce did, allow null data
        *
        * @param data JSON array containing station data
        * @return ArrayList of Station objects
        */
		private Set<Station> jarray_to_stations(Json.Array data)
		{
			var stations = new HashSet<Station>();

            if ( data != null )
            {
                data.foreach_element((array, index, element) => {
                    Station s = Station.make(element);
                    stations.add(s);
                });
            } // if

            return stations;
        } // jarray_to_stations


        /**
        * @brief Converts a JSON node to a Tag object
        *
        * @param node JSON node representing a tag
        * @return Tag object
        */
		private DataProvider.Tag jnode_to_tag(Json.Node node)
		{
			return Json.gobject_deserialize(typeof(DataProvider.Tag), node) as DataProvider.Tag;
		} // jnode_to_tag


        /**
        * @brief Marshals JSON tag data into an array of Tag
        *
        * Not knowing what the produce did, allow null data
        *
        * @param data JSON array containing tag data
        * @return ArrayList of Tag objects
        */
		private Set<DataProvider.Tag> jarray_to_tags(Json.Array? data)
		{
			var tags = new HashSet<DataProvider.Tag>();

            if ( data != null )
            {
                data.foreach_element((array, index, element) => {
                    DataProvider.Tag s = jnode_to_tag(element);
                    tags.add(s);
                });
            } // if

            return tags;
        }   // jarray_to_tags


        /**
         * @brief Get all radio-browser.info API servers
         * 
         * Gets server list from Radio Browser DNS SRV record, 
         * and failing that, from the API
         *
         * @since 1.5.4
         * @return ArrayList of strings containing the resolved hostnames
         * @throw DataError if unable to resolve DNS records
         */
        private ArrayList<string> get_srv_api_servers() throws DataProvider.DataError 
        {
            var results = new ArrayList<string>();

            if ( app().is_offline ) return results;

            try {
                /*
                    DNS SRV record lookup 
                */
                var srv_targets = GLib.Resolver.get_default().lookup_service(SRV_SERVICE, SRV_PROTOCOL, SRV_DOMAIN, null);
                foreach (var target in srv_targets) {
                    results.add(target.get_hostname());
                } // foreach
            } catch (GLib.Error e) {
              @warning(@"Unable to resolve Radio-Browser SRV records: $(e.message)");
            } // try

            if (results.is_empty) 
            {
                /*
                    JSON API server lookup as SRV record lookup failed
                    Get the servers from the API itself from a round-robin server
                */
                try {
                    uint status_code;
  
                    var uri = build_uri(@"$(RBI_SERVERS)");
                    if (uri == null)
                    {
                        warning("get_srv_api_servers - Invalid URI for servers endpoint");
                        return results;
                    } // if

                    var stream = HttpClient.GET(uri, out status_code);

                    debug(@"response from $(_current_server)$(RBI_SERVERS): $(status_code)");

                    if (status_code == 200) {
                        Json.Node root_node;

                        try {
                            var parser = new Json.Parser();
                            parser.load_from_stream(stream);
                            root_node = parser.get_root();
                        } catch (Error e) {
                            throw new DataProvider.DataError.PARSE_DATA(@"RBI API get servers - unable to parse JSON response: $(e.message)");
                        } // try

                        if (root_node != null && root_node.get_node_type() == Json.NodeType.ARRAY) {
                            root_node.get_array().foreach_element((array, index_, element_node) => {
                                var object = element_node.get_object();
                                if (object != null) {
                                    var name = object.get_string_member("name");
                                    if (name != null && !results.contains(name)) {
                                        results.add(name);
                                    } // if
                                } // if
                            });
                        } // if
                    } // if
                } catch (Error e) {
                    warning("Failed to parse RBI APIs JSON response: $(e.message)");
                } // try
            } // if

            debug(@"Results $(results.size)");

            return results;
        } // get_srv_api_servers


        /**
        * Encodes a text string for use in RadioBrowser API requests.
        *
        * This method ensures that the text is properly encoded for use in URLs
        * by converting special characters into their URL-safe equivalents.
        *
        * @param tag The text string to be encoded
        * @return A URL-encoded string representation of the input text
        */
		private static string encode_text(string tag)
        {
            // Percent-encode everything except unreserved characters (and the comma used as
            // the tag-list separator). This covers spaces, quotes, brackets, backslashes,
            // non-ASCII text etc. that previously produced an invalid URI and a libsoup
            // "soup_uri_is_valid" critical. It also fixes ':' which was mapped to %3B.
            return Uri.escape_string (tag, ",", false);
        } // encode_tag
    } // RadioBrowser
} // Providers
