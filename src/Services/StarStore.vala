/**
 * SPDX-FileCopyrightText: Copyright © 2020-2024 Louis Brauer <louis@brauer.family>
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file StarStore.vala
 *
 * @brief Store and retrieve a collection of starred stations.
 * 
 * Manages a collection of stations stored in a JSON file.
 * Provides methods to add, remove, and persist stations.
 * The JSON file store a subset of station data - the minimum
 * to be able to play a station without retrieving its information]
 * from radio-browser
 */

using Gee;
using GLib;
using Tuner.Models;
using Tuner.Services;


/**
 * @class StarStore
 *
 * @brief Manages a collection of starred stations and saved searches
 * 
 * This class allows for storing, retrieving, and persisting a 
 * list of favorite stations in a JSON file. It uses libgee for data structures.
 *
 * DirectoryController uses StationStore to load the starred stations from RadioBrowser
 */
public class Tuner.Services.StarStore : Object 
{

    private const string FAVORITES_PROPERTY_APP = "app";
    private const string FAVORITES_PROPERTY_FILE = "file";
    private const string FAVORITES_PROPERTY_SCHEMA = "schema";
    private const string FAVORITES_PROPERTY_STATIONS = "stations";
    private const string FAVORITES_PROPERTY_SEARCHES = "searches";

    private const string FAVORITES_SCHEMA_VERSION = "2.0";

    private const string M3U8 = "#EXTM3U\n#EXTENC:UTF-8\n#PLAYLIST:Tuner\n";
    private const string M3U8_UUID = "STATIONUUID"; 
    private const string UUID_REGEX = "([a-fA-Z0-9]{8}-[a-fA-Z0-9]{4}-[a-fA-Z0-9]{4}-[a-fA-Z0-9]{4}-[a-fA-Z0-9]{12})";
    private  Regex uuid_regex;

    construct 
    {
        try {
            uuid_regex = new Regex (UUID_REGEX, 0, 0);
         } catch ( RegexError e )
         {
           critical(@"Could not compile regex: $(e.message)");
         }
    }

    private File _starred_file; ///< File to persist favorite stations.


    private Map<string,Station> _starred_station_map = new HashMap<string, Station> (); ///< Collection of starred stations by UUID.
    private Gee.ArrayList<string> _starred_station_order = new Gee.ArrayList<string>(); ///< Persisted order of starred station UUIDs.
    private Gee.Set<string> _saved_searches = new HashSet<string> (); ///< Collection of saved searches.
    private bool _loaded = false;


    // ----------------------------------------------------------
    // Publics
    // ----------------------------------------------------------

    /**
     * @brief Constructor for StationStore.
     * @param favorites_path The path to the JSON file where favorites are stored.
     */
    public StarStore (File starred_file)
    {
        Object ();
        _starred_file =  starred_file;

    } // StarredStationController

    
    /**
     * @brief Adds a station to the favorites and persists the change.
     * @param station The station to be added.
     */
    public void add_station (Station station) {
        if (_starred_station_map.has_key (station.stationuuid)) return;
        _starred_station_map.set (station.stationuuid, station);
        _starred_station_order.add (station.stationuuid);
        persist ();
        app().events.starred_stations_changed_sig ( station );
    } // add_station


    /**
     * @brief Removes a station from the favorites and persists the change.
     *
     * @param station The station to be removed.
     */
     public void remove_station (Station station) {
        _starred_station_map.unset (station.stationuuid);
        _starred_station_order.remove (station.stationuuid);
        persist ();
        app().events.starred_stations_changed_sig ( station );
    } // remove_station


    /**
     * @brief Add or removes a station from the favorites and persists the change.
     *
     * @param station The station.
     */
     public void update_from_station (Station station) 
     {
        if ( station.starred ) 
        { 
            add_station (station); 
        }
        else 
        { 
            remove_station (station); 
        }
    } // remove_station


    /**
     * @brief Adds a saved search
     *
     * @param search_text The search term to save
     */
    public void add_saved_search(string search_text)
    {
        _saved_searches.add (search_text);
        persist();
    } // add_saved_search


    /**
     * @brief Removes a saved search
     *
     * @param search_text The search term to remove
     */
    public void remove_saved_search(string search_text)
    {
        _saved_searches.remove (search_text);
        persist();
    } // remove_saved_search


    /**
     * @brief Serializes the current favorites to a JSON string.
     *
     * @return A JSON string representation of the favorites.
     */
     public string serialize () 
     {
        Json.Builder builder = new Json.Builder ();
        builder.begin_object ();
	    builder.set_member_name (FAVORITES_PROPERTY_APP);
	    builder.add_string_value (Application.APP_ID);
	    builder.set_member_name (FAVORITES_PROPERTY_FILE);
	    builder.add_string_value (Application.STARRED);
	    builder.set_member_name (FAVORITES_PROPERTY_SCHEMA);
	    builder.add_string_value (FAVORITES_SCHEMA_VERSION);

        // Starred Stations
	    builder.set_member_name (FAVORITES_PROPERTY_STATIONS);
        builder.begin_array ();
        foreach (var uuid in _starred_station_order) {
            var starred = _starred_station_map.get (uuid);
            if (starred == null)
                continue;
            var node = Json.gobject_serialize (starred);
            builder.add_value (node);
        }
        // Append any stations not tracked in order (defensive).
        foreach (var starred in _starred_station_map.values) {
            if (_starred_station_order.contains (starred.stationuuid))
                continue;
            var node = Json.gobject_serialize (starred);
            builder.add_value (node);
        }
        builder.end_array ();

        // Saved Searches
	    builder.set_member_name (FAVORITES_PROPERTY_SEARCHES);
        builder.begin_array ();
        foreach (var searched in _saved_searches) {
            builder.add_string_value (searched);
        }
        builder.end_array ();
        builder.end_object ();

        Json.Generator generator = new Json.Generator ();
        generator.set_pretty (true);
        generator.set_root (builder.get_root ());
        string data = generator.to_data (null);
        return data;
    } // serialize


    /**
     * @brief Retrieves all favorite stations.
     *
     * @return An ArrayList of favorite stations.
     */
     public Collection<Station> get_all_stations () {
        // Return stations in persisted order (falling back to any missing entries).
        var ordered = new Gee.ArrayList<Station>();
        var seen = new Gee.HashSet<string>();
        foreach (var uuid in _starred_station_order)
        {
            var station = _starred_station_map.get (uuid);
            if (station == null)
                continue;
            ordered.add (station);
            seen.add (uuid);
        }
        foreach (var station in _starred_station_map.values)
        {
            if (!seen.contains (station.stationuuid))
                ordered.add (station);
        }
        return ordered;
    } // get_all_stations


    /**
     * @brief Reorders starred stations and persists the change.
     *
     * @param stationuuids The ordered list of station UUIDs.
     */
    public void reorder_stations (Gee.List<string> stationuuids)
    {
        if (stationuuids == null)
            return;

        _starred_station_order.clear ();
        foreach (var uuid in stationuuids)
        {
            if (_starred_station_map.has_key (uuid))
                _starred_station_order.add (uuid);
        }
        // Append any stations not present in the reorder list.
        foreach (var uuid in _starred_station_map.keys)
        {
            if (!_starred_station_order.contains (uuid))
                _starred_station_order.add (uuid);
        }
        persist ();
    } // reorder_stations
    

    /**
     * @brief Retrieves all favorite stations.
     *
     * @return An ArrayList of favorite stations.
     */
     public Gee.Set<string> get_all_searches () {
        return _saved_searches;
    } // get_all_searches
    

    /**
     * @brief Checks if a station is in the favorites.
     *
     * @param station The station to check.
     * @return True if the station is in favorites, false otherwise.
     */
    public bool contains (Station station) {
        return _starred_station_map.has_key (station.stationuuid);
    } // contains


    /**
     * @brief Updates a station in the favorites.
     *
     * @param station The station to update.
     */
    public void update(Station station)
    {
        if ( _starred_station_map.has_key (station.stationuuid) )
        {
            _starred_station_map.set (station.stationuuid, station.updated ());
            persist ();
        }
    } // update


    /**
     * @brief Loads the favorites from the JSON file.
     *
     * Starred stations are defined by the file and do not load from the DataProvider
     * and so can deviate. If the station disappears from the DataProvider, a copy
     * of its info remain in the starred file.
     * Load needs to happen after Application creation. 
     * 
     * This method reads the JSON file and populates the _store with
     * the favorite stations.
     */
    public async void load () {

        if ( _loaded) return;
        _loaded = true;
        debug ("store file initial creation");
        try 
        // Create file if it does not already exist
        {
            _starred_file.create (FileCreateFlags.PRIVATE).close ();
            //df.close ();
            debug (@"store created");
        } catch (Error e) {
            // File already exists
        }

        debug ("loading store");
        Json.Parser parser = new Json.Parser.immutable_new ();
        
        try {
            var stream = _starred_file.read ();
            parser.load_from_stream (stream);
            stream.close ();
        } catch (Error e) {
            warning (@"Load failed with error: $(e.message)");
        }

        Json.Node? root = parser.get_root ();

        if ( root == null ) return; // No favorites stored  

        Json.Array jstarred;
        Json.Array jsearches;

        // Check for schema versions
        if ( get_member( root, FAVORITES_PROPERTY_SCHEMA) == null ) 
        /*
            v1 Schema
        */
        {
            jstarred = root.get_array ();
            jsearches = null;
        }
        else
        /*
            v2+ Schema
        */
        {
            var stations = get_member( root, FAVORITES_PROPERTY_STATIONS);
            jstarred = stations.get_array ();            
            var searches = get_member( root, FAVORITES_PROPERTY_SEARCHES);
            jsearches = searches.get_array ();
        }

        /*
            Read in each starred item
        */
        _starred_station_order.clear ();
        jstarred.foreach_element ((a, i, elem) => 
        {           
            var station = new Station.basic(elem); // Creates a basic station without adding it to the main station directory
            _starred_station_map.set (station.stationuuid, station);
            _starred_station_order.add (station.stationuuid);

            station.starred = true;

            // Connect the star button
            station.station_star_changed_sig.connect ( (starred) => 
            {
                update_from_station ( station );
            }); 
        });

        // Check starred station currency - doing this way means once call to DataProvider for all the stations
        try {
            var provider_station = app().provider.by_uuids( _starred_station_map.keys);
            foreach ( var ps in provider_station)
            {
                var ss = _starred_station_map.get (ps.stationuuid);
                if ( ss != null) ss.is_in_index = ss.set_up_to_date_with (ps);
            }
        }
        catch (DataProvider.DataError e) {
            warning(@"Comparing with DataProvider copy of station: $(e.message)");
        }

        // Read each stored search
        jsearches.foreach_element ((a, i, elem) => {    
            _saved_searches.add (elem.get_string ());
            debug(@"Search:$(elem.get_string ())");
        }); // jsearches.foreach_element

    } // load
      

    /**
     * @brief Creates a string of Starred stations in m3u format
     * @return A string representation of the favorites formatted as M3U
     */
     public string export_m3u8()
     {
         StringBuilder playlist = new StringBuilder(M3U8);
         foreach (var uuid in _starred_station_order)
         {
             var station = _starred_station_map.get (uuid);
             if (station == null)
                 continue;
             var url = ( station.urlResolved == null || station.urlResolved == "") ? station.url : station.urlResolved;
             playlist.append (@"\n#EXT-X-MEDIA:$M3U8_UUID=\"$(station.stationuuid)\"\n");
             playlist.append (@"#EXTINF:-1,$(station.name)\n$(url)\n");
         }
 
         return playlist.str;
 
     } // export_m3u8
 
 
     /**
      * @brief Scans data for Station UUIDs which are checked and added as Starred.
      * @param data_stream The data to be scanned
      */
     public void import_stationuuids( DataInputStream data_stream ) throws GLib.IOError
     {
         Gee.List<string> stationuuids = new ArrayList<string>();
         string content;
         MatchInfo match_info;
         while ( (content = data_stream.read_line(null)) != null) 
         {                    
             uuid_regex.match (content, 0, out match_info); 
             while (match_info.matches ()) 
             {
                 stationuuids.add (match_info.fetch_all()[0]);
                 debug   (@"UUID: $(match_info.fetch_all()[0])");
                
                 try {
                     match_info.next ();
                 } catch ( RegexError e) 
                 {
                     warning   (@"Regex error processing line: $content\n Error: $(e.message)");
                 }
             } // while
         } // while
         
         foreach ( var station in app().directory.get_stations_by_uuid(stationuuids))
         {
            add_station(station);
         }
     } // import_stationuuids
 
 

    // ----------------------------------------------------------
    // Privates
    // ----------------------------------------------------------

 
 
    /**
     * @brief Persists the current state of favorites to the JSON file.
     * 
     * This method serializes the _store and writes it to the favorites file.
     */
    private void persist () 
    {
        debug ("persisting store");

        try {
            _starred_file.delete ();  
            var stream = _starred_file.create (
                FileCreateFlags.REPLACE_DESTINATION | FileCreateFlags.PRIVATE
            );
            var s = new DataOutputStream (stream);
            s.put_string ( serialize () );
            s.flush ();
            s.close (); // closes base stream also
        } catch (Error e) {
            warning (@"Persist failed with error: $(e.message)");
        }
    } // persist


    /**
     * @brief Returns the given property from the JSON node.
     * 
     */
    private static Json.Node? get_member(Json.Node node, string property_name) {
        // Check if the node is of type OBJECT
        if (node.get_node_type() == Json.NodeType.OBJECT) {
            Json.Object json_object = node.get_object();
    
            // Check if the JSON object has the specified property
            if ( json_object.has_member(property_name) ) 
                return json_object.get_member (property_name);
        }
        return null; // Not an object, so no properties exist
    } // get_member
} // StarStore
