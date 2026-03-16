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
         * @return String representation of the SortOrder
         */
        public string to_string() {
            switch (this) {
                case NAME:
                    return "name";
                case URL:
                    return "url";
                case HOMEPAGE:
                    return "homepage";
                case FAVICON:
                    return "favicon";
                case TAGS:
                    return "tags";
                case COUNTRY:
                    return "country";
                case STATE:
                    return "state";
                case LANGUAGE:
                    return "language";
                case VOTES:
                    return "votes";
                case CODEC:
                    return "codec";
                case BITRATE:
                    return "bitrate";
                case LASTCHECKOK:
                    return "lastcheckok";
                case LASTCHECKTIME:
                    return "lastchecktime";
                case CLICKTIMESTAMP:
                    return "clicktimestamp";
                case CLICKCOUNT:
                    return "clickcount";
                case CLICKTREND:
                    return "clicktrend";
                case RANDOM:
                    return "random";
                default:
                    assert_not_reached();
            }
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
         * @brief Initialize the DataProvider implementation
         *
         * @return true if initialization successful
         */
        public abstract bool initialize();


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
         * @brief Get all available tags
         *
         * @return ArrayList of Tag objects
         * @throw DataError if unable to retrieve or parse tag data
         */
         public abstract Set<Tag> get_tags(int offset = 0, int limit = 0) throws DataError;


        /**
         * @brief Get a station or stations by UUID/S
         *
         * @param uuids comma separated lists of the stations to retrieve
         * @return Station object if found, null otherwise
         * @throw DataError if unable to retrieve or parse station data
         */
         public abstract Set<Station> by_uuid(string uuids) throws DataError;
         public abstract Set<Station> by_uuids(Collection<string> uuids) throws DataError;

        /**
         * @brief Get a station or stations by Streaming URL  
         *
         * @param url streaming url the stations to retrieve
         * @return Station object if found, null otherwise
         * @throw DataError if unable to retrieve or parse station data
         */
         //public abstract Set<Model.Station> by_url(string url) throws DataError;  // TODO Not working at Provider

/**
 * @brief Search for stations based on given parameters
 *
 * @param params Search parameters
 * @param rowcount Maximum number of results to return
 * @param offset Offset for pagination
 * @return ArrayList of Station objects matching the search criteria
 * @throw DataError if unable to retrieve or parse station data
 */
		public abstract Set<Station> search(SearchParams params, uint rowcount, uint offset             = 0) throws DataError;
		public async abstract Set<Station> search_async(SearchParams params, uint rowcount, uint offset = 0) throws DataError;

    } // API
} // DataProvider