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

        public StationListBoxPager(StationSet? data)
        {
            _data = data;
        }

        /**
        * @brief Retrieves the next page of stations from the data source
        * @return A Set of Model.Station objects, or null if no data source exists
        * @throws SourceError If there's an error retrieving the next page
        */
        public Set<Station>? next_page () throws SourceError
        {
            if ( _data == null ) return null;
            return _data.next_page();
        }
    } // StationListBoxPager
} // Tuner
