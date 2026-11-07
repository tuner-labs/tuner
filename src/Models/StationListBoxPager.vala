/*
 * SPDX-FileCopyrightText: 2020-2022 Louis Brauer <louis@brauer.family>
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using Gee;
using Tuner.Models;

namespace Tuner.Models
{
    /**
    * @class StationListBoxPager
    * @brief Handles paging and data access for StationListBox.
    */
    public class StationListBoxPager : Object
    {
        private StationSet? _data;

        /**
         * @brief Creates a pager over a station set.
         *
         * @param data The station set to page through, or null for none.
         */
        public StationListBoxPager(StationSet? data)
        {
            _data = data;
        }

        /**
        * @brief Retrieves the next page of stations without blocking the caller
        * @param priority Priority of the HTTP request; GLib.Priority.LOW for background loads
        * @return A Set of Model.Station objects, or null if no data source exists
        * @throws SourceError If there's an error retrieving the next page
        */
        public async Set<Station>? next_page_async (int priority = GLib.Priority.HIGH_IDLE) throws SourceError
        {
            if ( _data == null ) return null;
            return yield _data.next_page_async(priority);
        }
    } // StationListBoxPager
} // Tuner
