/**
 * SPDX-FileCopyrightText: Copyright © 2020-2024 Louis Brauer <louis@brauer.family>
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file StarStore.vala
 *
 * @brief Store and retrieve a collection of starred stations and saved searches.
 * 
 * Manages a collection of stations, searches stored in a JSON file.
 * Provides methods to add, remove, and persist stations and searches.
 * The JSON file store a subset of station data - the minimum required to be able to 
 * play a station without retrieving its information from radio-browser, plus state 
 * information such as when it was starred, when it was last played and how many times it has been played.
 * 
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
    // JSON file constants
    private const string FAVORITES_PROPERTY_APP = "app";
    private const string FAVORITES_PROPERTY_FILE = "file";
    private const string FAVORITES_PROPERTY_SCHEMA = "schema";
    private const string FAVORITES_PROPERTY_STATIONS = "stations";
    private const string FAVORITES_PROPERTY_SEARCHES = "searches";
    private const string STATION_PROPERTY_NOTE = "note";   // The user's note, saved with the station

    /** @brief Longest station note, in characters. */
    public const int NOTE_MAX_CHARS = 500;

    private const string FAVORITES_SCHEMA_VERSION = "2.0";

    // M3U8 export constants
    private const string M3U8 = "#EXTM3U\n#EXTENC:UTF-8\n#PLAYLIST:Tuner\n";
    private const string M3U8_UUID = "STATIONUUID"; 
    private const string M3U8_NOTE = "#TUNER-NOTE:";   // Followed by the escaped note, on the line after the station's media line
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
    private Map<string,string> _notes = new HashMap<string, string> (); ///< The user's note for starred stations, by UUID.
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
        _notes.unset (station.stationuuid);   // Notes are only for starred stations
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
     * @brief Whether a starred station has a note.
     */
    public bool has_note(string stationuuid)
    {
        return _notes.has_key (stationuuid);
    } // has_note


    /**
     * @brief The note on a starred station, or an empty string if it has none.
     */
    public string get_note(string stationuuid)
    {
        return _notes.has_key (stationuuid) ? _notes.get (stationuuid) : "";
    } // get_note


    /**
     * @brief Sets the note on a starred station and saves it with the station.
     *
     * Notes are only kept for starred stations, so this does nothing for any other station.
     * Blank text removes the note; text over NOTE_MAX_CHARS is cut to fit.
     *
     * @param stationuuid The starred station.
     * @param text The note text.
     */
    public void set_note(string stationuuid, string text)
    {
        if (!_starred_station_map.has_key (stationuuid))
            return;

        var note = clean_note (text);
        if (note == "")
        {
            if (!_notes.unset (stationuuid))
                return;
        }
        else
        {
            if (_notes.has_key (stationuuid) && _notes.get (stationuuid) == note)
                return;
            _notes.set (stationuuid, note);
        }
        persist ();
    } // set_note


    /**
     * @brief Trims a note and cuts it to NOTE_MAX_CHARS characters.
     */
    private static string clean_note(string text)
    {
        var note = text.strip ();
        if (note.char_count () > NOTE_MAX_CHARS)
            note = note.substring (0, note.index_of_nth_char (NOTE_MAX_CHARS)).strip ();
        return note;
    } // clean_note


    /**
     * @brief Serializes a starred station, with its note if it has one.
     */
    private Json.Node serialize_station(Station station)
    {
        var node = Json.gobject_serialize (station);
        if (_notes.has_key (station.stationuuid))
            node.get_object ().set_string_member (STATION_PROPERTY_NOTE, _notes.get (station.stationuuid));
        return node;
    } // serialize_station


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
            var node = serialize_station (starred);
            builder.add_value (node);
        }
        // Append any stations not tracked in order (defensive).
        foreach (var starred in _starred_station_map.values) {
            if (_starred_station_order.contains (starred.stationuuid))
                continue;
            var node = serialize_station (starred);
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

        // Serialize
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

            // The user's note on the station, if any
            var jstation = elem.get_object ();
            if (jstation != null && jstation.has_member (STATION_PROPERTY_NOTE))
            {
                var note = clean_note (jstation.get_string_member (STATION_PROPERTY_NOTE));
                if (note != "")
                    _notes.set (station.stationuuid, note);
            }

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
             if (_notes.has_key (station.stationuuid))
                 playlist.append (M3U8_NOTE + escape_note (_notes.get (station.stationuuid)) + "\n");
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
         var imported_notes = new HashMap<string,string>();
         string? media_uuid = null;     // Station of the most recent media line; the note line that follows belongs to it
         string content;
         MatchInfo match_info;
         while ( (content = data_stream.read_line(null)) != null) 
         {                    
             if ( content.has_prefix (M3U8_NOTE) )
             {
                 if ( media_uuid != null )
                     imported_notes.set (media_uuid, clean_note (unescape_note (content.substring (M3U8_NOTE.length))));
                 continue;
             }

             bool is_media_line = content.contains (M3U8_UUID);
             uuid_regex.match (content, 0, out match_info); 
             while (match_info.matches ()) 
             {
                 var found = match_info.fetch_all()[0];
                 stationuuids.add (found);
                 if ( is_media_line )
                     media_uuid = found;
                 debug   (@"UUID: $found");
                
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

         // Notes from the file, for starred stations that do not already have one
         bool notes_added = false;
         foreach ( var item in imported_notes.entries )
         {
             if ( item.value != "" && _starred_station_map.has_key (item.key) && !_notes.has_key (item.key) )
             {
                 _notes.set (item.key, item.value);
                 notes_added = true;
             }
         }
         if ( notes_added )
             persist ();
     } // import_stationuuids


     /**
      * @brief Makes a note safe for one line of an M3U8 file: backslash and line breaks are escaped.
      */
     private static string escape_note( string note )
     {
         return note.replace ("\\", "\\\\").replace ("\r", "").replace ("\n", "\\n");
     } // escape_note


     /**
      * @brief Reverses escape_note.
      */
     private static string unescape_note( string text )
     {
         var note = new StringBuilder ();
         for ( int index = 0; index < text.length; index++ )
         {
             if ( text[index] == '\\' && index + 1 < text.length )
             {
                 index++;
                 note.append_c ( text[index] == 'n' ? '\n' : text[index] );
             }
             else
             {
                 note.append_c ( text[index] );
             }
         }
         return note.str;
     } // unescape_note
 
 

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
