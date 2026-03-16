/**
 * SPDX-FileCopyrightText: Copyright © 2020-2024 Louis Brauer <louis@brauer.family>
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file DirectoryController.vala
 *
 * @brief Station Directories and their population
 *
 */

using Gee;
using Tuner.Models;
using Tuner.Services;

/**
 * @brief Error domain for source-related errors.
 */
public errordomain SourceError {
    UNAVAILABLE
}



/**
 * Controller class responsible for managing directory-related operations in the Tuner application.
 *
 * This class handles various directory management tasks,
 * such as file system operations, directory navigation, and file monitoring within the
 * context of the Tuner namespace.
 */
public class Tuner.Controllers.DirectoryController : Object
{

    private const uint DIRECTORY_LIMIT = 41;

    private DataProvider.API _provider;
    private StarStore _star_store;
    private bool _loaded = false;

    public signal void tags_updated (Set<DataProvider.Tag> tags);

	public string provider_name()
	{
		return _provider.name();
	}

    /**
     * @brief Constructor for DirectoryController.
     *
     * @param store The StationStore to use for managing stations.
     */
    public DirectoryController (DataProvider.API provider, StarStore star_store) {  
        Object();
        _provider = provider;
        _star_store = star_store;
    } // DirectoryController


	public string provider()
	{
		return _provider.name();
	} // provider

	/**
	* @brief Initializes the provider and starts the load of Saved Stations
	*
	*/
	public void load()
	{
		if (_loaded || app().is_offline)
			return;

        _provider.initialize();
        _star_store.load.begin();
        _loaded = true;
    } // load


	/**
	* @brief Get a collection of Station station by its UUID.
	*
	* @param uuid The UUID of the station to load.
	* @return A StationSet object for the requested station.
	* @todo radio-browser should handle multiple UUID on a query, but is broken
	*/
	public Set<Models.Station> get_stations_by_uuid (Collection<string> uuids)
	{
		try
		{
			return _provider.by_uuids(uuids);
		} catch (DataProvider.DataError e)
		{
			critical (@"$(_provider.name()) unavailable");
		}
		return new HashSet<Station>();
	} // get_stations_by_uuid


    /**
     * @brief Get a collection of Station station by its stream URL. // TODO Not working at Provider
     *
     * @param uuid The URL of the station to load.
     * @return A StationSet object for the requested station.
     * @todo radio-browser should handle URL queries, but is broken
     */
    //  public Set<Model.Station> get_station_by_url (string url) {
    //      try {
    //          return _provider.by_url(url);
    //      } catch (Tuner.DataProvider.DataError e) {
    //          critical (@"$(_provider.name) unavailable");
    //      }
    //      return new HashSet<Model.Station>();
    //  } // get_station_by_url


	/**
	* @brief Load a station by its UUID.
	*
	* @param uuid The UUID of the station to load.
	* @return A StationSet object for the requested station.
	*/
	public StationSet load_station_uuid (string uuid)
	{
		debug(@"LBU UUID: $uuid ");
		var params = DataProvider.SearchParams() 
		{
			uuids = new HashSet<string>()
		};
		params.uuids.add (uuid);
		var source = new StationSet(1, params, _provider, _star_store);
		return source;
	} // load_station_uuid


	/**
	* @brief Load a set of random stations.
	*
	* @param limit The maximum number of stations to load.
	* @return A StationSet object with random stations.
	*/
	public StationSet load_random_stations (uint limit)
	{
		var params = DataProvider.SearchParams() {
			text        = "",
			countrycode = "",
			tags        = new HashSet<string>(),
			order       = DataProvider.SortOrder.RANDOM
		};
		var source = new StationSet(limit, params, _provider, _star_store);
		return source;
	} // load_random_stations


	/**
	* @brief Load trending stations.
	*
	* @param limit The maximum number of stations to load.
	* @return A StationSet object with trending stations.
	*/
	public StationSet load_trending_stations (uint limit)
	{
		var params = DataProvider.SearchParams() {
			text        = "",
			countrycode = "",
			tags        = new HashSet<string>(),
			order       = DataProvider.SortOrder.CLICKTREND,
			reverse     = true
		};
		var source = new StationSet(limit, params, _provider, _star_store);
		return source;
	} // load_trending_stations


	/**
	* @brief Load popular stations.
	*
	* @param limit The maximum number of stations to load.
	* @return A StationSet object with popular stations.
	*/
	public StationSet load_popular_stations (uint limit)
	{
		var params = DataProvider.SearchParams() {
			text        = "",
			countrycode = "",
			tags        = new HashSet<string>(),
			order       = DataProvider.SortOrder.CLICKCOUNT,
			reverse     = true
		};
		var source = new StationSet(limit, params, _provider, _star_store);
		return source;
	} // load_popular_stations


	/**
	* @brief Load stations by country code.
	*
	* @param limit The maximum number of stations to load.
	* @param countrycode The country code to filter stations.
	* @return A StationSet object with stations from the specified country.
	*/
	public StationSet load_by_country (uint limit, string countrycode)
	{
		var params = DataProvider.SearchParams () {
			text        = "",
			countrycode = countrycode,
			tags        = new HashSet<string>(),
			order       = DataProvider.SortOrder.CLICKCOUNT,
			reverse     = true
		};
		var source = new StationSet(limit, params, _provider, _star_store);
		return source;
	} // load_by_country


	/**
	* @brief Load stations based on search text.
	*
	* @param utext The search text to filter stations.
	* @param limit The maximum number of stations to load.
	* @return A StationSet object with stations matching the search text.
	*/
	public StationSet load_search_stations (string utext, uint limit)
	{
		var params = DataProvider.SearchParams() {
			text        = utext,
			countrycode = "",
			tags        = new HashSet<string>(),
			order       = DataProvider.SortOrder.CLICKCOUNT,
			reverse     = true
		};
		var source = new StationSet(limit, params, _provider, _star_store);
		return source;
	} // load_search_stations


    /**
     * @brief Get all starred stations.
     *
     * @return An Collection of starred Model.Station objects.
     */
    public Collection<Station> get_starred () {
        return _star_store.get_all_stations();
    } // get_starred


    /**
     * @brief Reorders starred stations and persists the change.
     *
     * @param stationuuids The ordered list of station UUIDs.
     */
    public void reorder_starred (Gee.List<string> stationuuids)
    {
        _star_store.reorder_stations (stationuuids);
    } // reorder_starred


// --------------------------------------------------

    /**
     * @brief Adds a saved search term and returns the StationSet to retrieve the stations found
     *
     * @return A StationSet object with stations 
     */
    public StationSet add_saved_search( string search_term)
    {
        _star_store.add_saved_search ( search_term);
        return load_search_stations(search_term,DIRECTORY_LIMIT);
    } // add_saved_search


    /**
     * @brief Removed the given saved search term
     *
     */
    public void remove_saved_search( string search_text)
    {
        _star_store.remove_saved_search ( search_text);
    } // remove_saved_search


    /**
     * @brief Loads stations found from each saved search term
     *
     * @return A map of search terms and related StationSet object with stations 
     */
    public Map<string, StationSet> load_saved_searches()
    {
        Map<string, StationSet> searches = new HashMap<string, StationSet>();
        foreach( var search in _star_store.get_all_searches ())
        {
            searches.set (search, load_search_stations(search,DIRECTORY_LIMIT));
        }
        return searches;
    } // load_saved_searches


    // -------------------------------------------------

	/**
	* @brief Load stations by tags.
	*
	* @param utag An ArrayList of tags to filter stations.
	* @return A StationSet object with stations matching the given tags.
	*/
	public StationSet load_by_tag (string utag)
	{
		var t =new HashSet<string>();
		t.add (utag.down());
		var params = DataProvider.SearchParams() {
			text        = "",
			countrycode = "",
			tags        = t,
			order       = DataProvider.SortOrder.VOTES,
			reverse     = true
		};
		var source = new StationSet(40, params, _provider, _star_store);
		return source;
	} // load_by_tag


	/**
	* @brief Count a click for a station.
	*
	* @param station The station that was clicked.
	*/
	public StationSet load_by_tag_set (Set<string> utags)
	{
		var params = DataProvider.SearchParams() {
			text        = "",
			countrycode = "",
			tags        = utags,
			order       = DataProvider.SortOrder.VOTES,
			reverse     = true
		};
		var source = new StationSet(40, params, _provider, _star_store);
		return source;
	} // load_by_tag_set


	/**
	* @brief Count a click for a station.
	*
	* @param station The station that was clicked.
	*/
	public void count_station_click (Station station)
	{
		if (!app().settings.do_not_vote)
		{
			debug (@"Send listening event for station $(station.stationuuid)");
			_provider.click (station.stationuuid);
		}
		else
		{
			debug ("do-not-vote enabled, will not send listening event");
		}
	} // count_station_click


	/**
	* @brief Load tags from the _provider.
	*/
	public void load_tags ()
	{
		try
		{
			var tags = _provider.get_tags ();
			tags_updated (tags);
		} catch (DataProvider.DataError e)
		{
			warning (@"Load tags failed with error: $(e.message)");
		}
	} // load_tags


	public Set<DataProvider.Tag> load_random_genres(int genres)
	{
		Set<DataProvider.Tag> result = new HashSet<DataProvider.Tag>();

		while (app().is_online && result.size < genres)
		{
			try
			{
				var offset = Random.int_range(0, _provider.available_tags());
				var tag    = _provider.get_tags (offset,1);// Get a random tag
				result.add_all (tag);
			} catch (Error e)
			{
			}
		}
		return result;
	} // load_random_genres
} // DirectoryController


/**
 * @brief A pageable set of Stations
 */
public class Tuner.StationSet : Object
{
	private uint _offset    = 0;
	private uint _page_size = 20;
	private bool _more      = true;
	private DataProvider.SearchParams _params;
	private DataProvider.API _provider;
	private StarStore _star_store;

    /**
     * @brief Constructor for StationSet.
     *
     * @param limit The maximum number of stations to fetch.
     * @param params The search parameters for fetching stations.
     * @param client The RadioBrowser client to use for fetching stations.
     * @param star_store The StationStore to use for managing stations.
     */
    public StationSet (uint limit, 
                        DataProvider.SearchParams params, 
                        DataProvider.API client,
                        StarStore star_store) {
        Object ();
        // This disables paging for now
        _page_size = limit;
        _params = params;
        _provider = client;
        _star_store = star_store;
    } // StationSet


	/**
	* @brief Fetch the next set of stations.
	*
	* @return An ArrayList of Model.Station objects.
	* @throws SourceError If the source is unavailable.
	*/
	public Set<Station>? next_page () throws SourceError
	{

		if (app().is_offline)
			return null;

		// Fetch one more to determine if source has more items than page size
		try
		{
			var raw_stations = _provider.search (_params, _page_size + 1, _offset);
			// TODO Place filter here?
			// var filtered_stations = raw_stations.filter (filterByCountry);
			var filtered_stations = raw_stations.iterator ();

			var stations = convert_stations (filtered_stations);
			_offset += _page_size;
			_more    = stations.size > _page_size;
			if (_more)
				stations.remove(stations.to_array ()[(int)_page_size]);
			return stations;
		} catch (DataProvider.DataError e)
		{
			throw new SourceError.UNAVAILABLE("Directory Error");
		}
	} // next_page

	/**
	* @brief Fetch the next set of stations.
	*
	* @return An ArrayList of Model.Station objects.
	* @throws SourceError If the source is unavailable.
	*/
	public async Set<Station>? next_page_async () throws SourceError
	{

		if (app().is_offline)
			return null;

		// Fetch one more to determine if source has more items than page size
		try
		{
			var raw_stations = yield _provider.search_async(_params, _page_size + 1, _offset);
			// TODO Place filter here?
			// var filtered_stations = raw_stations.filter (filterByCountry);
			var filtered_stations = raw_stations.iterator ();

			var stations = convert_stations (filtered_stations);
			_offset += _page_size;
			_more    = stations.size > _page_size;
			if (_more)
				stations.remove(stations.to_array ()[(int)_page_size]);
			return stations;
		} catch (DataProvider.DataError e)
		{
			throw new SourceError.UNAVAILABLE("Directory Error");
		}
	} // next_page


	/**
	* @brief Check if there are more stations to fetch.
	*
	* @return true if there are more stations, false otherwise.
	*/
	public bool has_more ()
	{
		return _more;
	} // has_more


	/**
	* @brief Convert RadioBrowser.Station objects to Model.Station objects.
	*
	* @param raw_stations An iterator of RadioBrowser.Station objects.
	* @return An ArrayList of converted Model.Station objects.
	*/
	private Set<	Station> convert_stations (Iterator<Station> raw_stations)
	{
		var stations = new HashSet<Station> ();

		while (raw_stations.next())
		{
			var station = raw_stations.get ();
			station.station_star_changed_sig.connect (() =>
			{
				_star_store.update_from_station(station);
			});
			stations.add (station);
		}
		return stations;
	} // convert_stations
} // StationSet
