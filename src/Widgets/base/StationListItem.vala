/*
 * SPDX-FileCopyrightText: 2020-2022 Louis Brauer <louis@brauer.family>
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using Tuner.Models;
using Tuner.Widgets.Granite;

namespace Tuner.Widgets.Base
{
    /**
    * @class StationListItem
    * @brief A custom source list item that manages its own population state
    *
    * This class extends SourceList.Item to provide functionality for lazy-loading
    * content and managing the populated state of radio station listings.
    *
    * @extends SourceList.Item
    */
    public class StationListItem : SourceList.Item
    {
        private bool _populated;
        private StationListBox _slb;

        /**
        * @brief Whether populate() loads stations in the background (true) or blocks until they arrive (false).
        *
        * Background loading keeps the UI responsive but shows the page empty until the stations
        * arrive; foreground loading shows the page complete. Display turns it off for Discover,
        * Trending and Popular.
        */
        public bool load_in_background { get; set; default = true; }

        /**
        * @brief Whether an empty first page is a normal result rather than a failed load.
        *
        * The Latest Search item has nothing to load until a search is run, because the search
        * controller fills it with results. For such items an empty page is not logged as a
        * problem and does not make the item load again when selected.
        */
        public bool empty_is_normal { get; set; default = false; }

        /**
        * @brief Constructs a new SourceListItem
        * @param title The display title for the item
        * @param slb The parent StationListBox this item belongs to
        * @param prepopulated Whether this item starts with populated content
        */
        public StationListItem(string title, StationListBox slb, bool prepopulated = false )
        {
            base (
                title
            );
            _slb = slb;
            _populated = prepopulated;
        }

        /**
        * @brief Populates the item with station data if not already populated
        * @param display The Display instance to hook up the station list
        *
        * This method checks if the item needs population and if the app is online,
        * then attempts to load the next page of stations. If successful, it hooks
        * up the station list to the display and updates the content.
        */
        public void populate( StationListHookup station_list, bool force = false )
        {
            if ( ( _populated && !force ) || app().is_offline ) return;
            _populated = true;

            // Loaded without blocking the UI. A page the user is waiting for is loaded at normal
            // priority, the rest in the background at the lowest.
            populate_async.begin (station_list, load_in_background ? Priority.LOW : Priority.HIGH_IDLE);
        } // populate


        /**
        * @brief Lets the item load again when the first load came back empty
        *
        * A failed request returns an empty page rather than an error, and without this the item
        * would count as populated and show nothing until the app was restarted. Selecting the item
        * again now tries again.
        *
        * @param page The page that was just loaded, or null
        */
        private void allow_retry_if_empty ( Gee.Collection<Station>? page )
        {
            if ( empty_is_normal )
                return;

            if ( page == null || page.size == 0 )
            {
                warning (@"Nothing loaded for '$(name)'; it will try again when selected");
                _populated = false;
            }
        } // allow_retry_if_empty


        /**
        * @brief Loads the first page in the background so selecting a category never freezes the UI
        * @param station_list The hookup that receives the loaded station list
        * @param priority Priority of the request: Priority.LOW for background work
        */
        private async void populate_async( StationListHookup station_list, int priority )
        {
            try {
                var page = yield _slb.pager.next_page_async (priority);
                var? slist = StationList.with_stations (page);
                if ( slist != null )
                {
                    _slb.attach_station_list (station_list, slist);
                }
                allow_retry_if_empty (page);
            } catch (SourceError e) {
                _populated = false;     // try again the next time it is selected
                _slb.show_alert ();
            }
        } // populate_async
    } // SourceListItem
} // Tuner
