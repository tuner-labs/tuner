/**
 * SPDX-FileCopyrightText: Copyright © 2020-2024 Louis Brauer <louis@brauer.family>
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file DataProvider.vala
 * 
 * @author technosf
 * @date 2024-12-01
 * @since 2.0.0
 * @brief Interface to radio-browser.info API and servers
 * 
 */

using Gee;
using Tuner.Models;

/**
 * @namespace Tuner.DataProvider
 *
 * @brief API for radio station information provider implementations
 *
 */
namespace Tuner.Services.DataProvider {

    /**
     * @struct SearchParams
     * @brief API search parameters 
     * 
     * Defines the search criteria used when querying the radio-browser.info API
     * for stations.
     */
    public struct SearchParams {
        /** @brief Search text to match against station names */
        string text;

        /** @brief List of tags to filter stations by */
        Set<string> tags;

        /** @brief List of specific station UUIDs to retrieve */
        Set<string> uuids;

        /** @brief ISO country code to filter stations by */
        string countrycode;

        /** @brief Sorting criteria for the results */
        SortOrder order;

        /** @brief Whether to reverse the sort order */
        bool reverse;
    }

    
    /**
     * @brief Error domain for DataProvider-related errors
     * 
     */
    public errordomain DataError {
        /** @brief Error parsing API response data */
        PARSE_DATA,

        /** @brief Unable to establish connection to API servers */
        NO_CONNECTION
    } // DataError


    /**
     * @enum SortOrder
     * @brief Enumeration of sorting options for station search results
     * 
     */
    public enum SortOrder {
        NAME,
        URL,
        HOMEPAGE,
        FAVICON,
        TAGS,
        COUNTRY,
        STATE,
        LANGUAGE,
        VOTES,
        CODEC,
        BITRATE,
        LASTCHECKOK,
        LASTCHECKTIME,
        CLICKTIMESTAMP,
        CLICKCOUNT,
        CLICKTREND,
        RANDOM;

        /**
         * @brief Convert SortOrder enum to string representation
         *
         * @return The lower-case name of the SortOrder, such as "clickcount"
         */
        public string to_string() {
            // The nick of each value is its lower-case name, which is what the API expects
            return ((EnumClass) typeof (SortOrder).class_ref ()).get_value (this).value_nick;
        } // to_string
    } // SortOrder


    /**
     * @class Tag
     *
     * @brief Represents a radio station tag with usage statistics
     * 
     * Encapsulates metadata about a tag used to categorize radio stations,
     * including its name and the number of stations using it.
     */
    public class Tag : Object {
        /** @brief The tag name */
        public string name { get; set; }

        /** @brief Number of stations using this tag */
        public uint stationcount { get; set; }
    } // Tag


    /**
     * @class API
     *
     * @brief Main DataProvider API 
     * 
     * Defines methods to interact with the DataProvider API, including:
     * - Station search and retrieval
     * - User interaction tracking (votes, listens)
     * - Tag management
     * - Server discovery and connection handling
     *
     */
    public interface API : Object 
    {
        /**
         * @brief DataProvider status
         *
         */
        public enum Status
        {
            OK,
            NO_SERVER_LIST,
            NO_SERVERS_PRESENTED,
            NOT_AVAILABLE,
            UNKNOWN_ERROR
        } // Status


        /**
         * @brief Clears the last data error 
         *
         */
         public virtual void clear_last_error() { last_data_error = null; }


        /**
         * @brief The last DataError from the DataProvider
         *
         */
         public abstract DataError? last_data_error { get; protected set; }


        /**
         * @brief DataProvider status property
         *
         */
         public abstract Status status { get; protected set; }


        /**
         * @brief DataProvider name property
         *
         */
        public abstract string name();


        /**
         * @brief Number of stations available
         *
         * @return the number of available stations
         */
         public abstract int available_stations();   

         /**
          * @brief Number of tags available
          *
          * @return the number of available tags
          */
         public abstract int available_tags();   


        /**
         * @brief Initialize the DataProvider implementation without blocking the UI
         *
         * Safe to call more than once and from several places at the same time: a call made while
         * initialization is running waits for that run to finish. Queries made while it runs wait too.
         *
         * @return true if initialization successful
         */
        public async abstract bool initialize_async();


        /**
         * @brief Register a station listen event
         *
         * @param stationuuid UUID of the station being listened to
         */
        public abstract void click(string stationuuid);


        /**
         * @brief Vote for a station
         *
         * @param stationuuid UUID of the station being voted for
         */
         public abstract void vote(string stationuuid) ;


        /**
         * @brief Get tags without blocking the UI
         *
         * @param offset position in the tag list to start from
         * @param limit number of tags wanted
         * @return the tags found
         * @throw DataError if the response cannot be parsed
         */
         public async abstract Set<Tag> get_tags_async(int offset = 0, int limit = 0) throws DataError;


        /**
         * @brief Get stations by UUID, without blocking the UI
         *
         * @param uuids the uuids of the stations to retrieve
         * @return the stations found
         * @throw DataError if unable to retrieve or parse station data
         */
         public async abstract Set<Station> by_uuids_async(Collection<string> uuids) throws DataError;

/**
 * @brief Search for stations based on given parameters, without blocking the UI.
 *
 * @param params Search parameters
 * @param rowcount Maximum number of results to return
 * @param offset Offset for pagination
 * @param priority Priority of the HTTP request: use GLib.Priority.LOW for background work nobody is
 * waiting for.
 * @return Station objects matching the search criteria
 * @throw DataError if unable to retrieve or parse station data
 */
		public async abstract Set<Station> search_async(SearchParams params, uint rowcount, uint offset = 0, int priority = GLib.Priority.HIGH_IDLE) throws DataError;

    } // API
} // DataProvider