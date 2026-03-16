/**
 * SPDX-FileCopyrightText: Copyright © 2020-2024 Louis Brauer <louis@brauer.family>
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file Display.vala
 *
 * @brief Defines the below-headerbar display of stations in the Tuner application.
 *
 * This file contains the Display class, which implements visual elements for
 * features such as a source list, content stack that display and manage Station
 * settings and handles user actions like station selection.
 *
 * @since 2.0.0
 *
 * @see Tuner.Application
 * @see Tuner.DirectoryController
 */


using Gee;
using Tuner.Controllers;
using Tuner.Models;
using Tuner.Services;
using Tuner.Widgets.Base;
using Tuner.Widgets.Granite;


/**
 * @brief Display class for managing organization and presentation of genres and their stations
 *
 * Display should be initialized and re-initialized by its owning class
 *
 * Display packs a source list and overlay of background icon and content stack
 */
public class Tuner.Widgets.Display : Gtk.Paned, StationListHookup {

	private const string BACKGROUND_TUNER                               = "tuner:background-tuner";
	private const string BACKGROUND_JUKEBOX                             = "tuner:background-jukebox";
	private const int EXPLORE_CATEGORIES                                = 5;     // How many explore categories to display
	private const double BACKGROUND_OPACITY                             = 0.15;
	private const int BACKGROUND_TRANSITION_TIME_MS                     = 1500;
	private const Gtk.RevealerTransitionType BACKGROUND_TRANSITION_TYPE = Gtk.RevealerTransitionType.CROSSFADE;


    /**
     * @brief Signal emitted when a station is clicked.
     * @param station The clicked station.
     */
    public signal void station_clicked_sig (Station station);

	/**
	 * @brief Handles focus entering the search entry.
	 */
	public void on_search_focused()
	{
		// Keep the current stack visible until results are ready.
	} // on_search_focused


	/**
	 * @brief Handles search text updates from the header bar.
	 *
	 * @param text Search text submitted by the header bar.
	 */
    public void on_search_requested(string text)
	{
		var search = text.strip();
		if (search.length == 0)
		{
			_pending_search_term = "";
			// Reset search results to the initial empty state.
			_search_controller.handle_search_for("");
			_search_results.tooltip_button.sensitive = false;
			_search_results.parameter = "";
			var empty = new StationList();
			station_list_hookup(empty);
			_search_results.content = empty;
			return;
        } // if
		_pending_search_term = search;
		_search_results.tooltip_button.sensitive = false;
		_search_controller.handle_search_for(search);
	} // on_search_requested


    /**
     * @property stack
     * @brief The stack widget for managing different views.
     */
    public Gtk.Stack stack { get; construct; }


    /**
     * @property source_list
     * @brief The source list widget for displaying categories.
     */
    public SourceList source_list { get; construct; }


    /**
     * @property directory
     * @brief The directory controller for managing station data.
     */
    public DirectoryController directory { get; construct; }


    /*
        Display Assets
    */

	private SourceList.ExpandableItem _selections_category     = new SourceList.ExpandableItem (_("Selections"));
	private SourceList.ExpandableItem _library_category        = new SourceList.ExpandableItem (_("Library"));
	private SourceList.ExpandableItem _saved_searches_category = new SourceList.ExpandableItem (_("Saved Searches"));
	private SourceList.ExpandableItem _explore_category        = new SourceList.ExpandableItem (_("Explore"));
	private SourceList.ExpandableItem _genres_category         = new SourceList.ExpandableItem (_("Genres"));
	private SourceList.ExpandableItem _subgenres_category      = new SourceList.ExpandableItem (_("Subgenres"));
	private SourceList.ExpandableItem _eras_category           = new SourceList.ExpandableItem (_("Eras"));
	private SourceList.ExpandableItem _talk_category           = new SourceList.ExpandableItem (_("Talk, News, Sport"));

	// Bitmask values for expanded source list sections (collapsible only).
	private const uint SOURCE_LIST_EXPANDED_SAVED_SEARCHES = 1u << 0;
	private const uint SOURCE_LIST_EXPANDED_EXPLORE        = 1u << 1;
	private const uint SOURCE_LIST_EXPANDED_GENRES         = 1u << 2;
	private const uint SOURCE_LIST_EXPANDED_SUBGENRES      = 1u << 3;
	private const uint SOURCE_LIST_EXPANDED_ERAS           = 1u << 4;
	private const uint SOURCE_LIST_EXPANDED_TALK           = 1u << 5;

	private bool _suppress_source_list_mask_write = false;


	private bool _first_activation           = true;     // display has not been activated before
	private bool _active                     = false;     // display is active
	private bool _shuffle                    = false;     // Shuffle mode
	private Application _app;
	private PlayerController _player;
	private StarStore _stars;
	private DataProvider.API _provider;
	private Gtk.Revealer _background_tuner   = new Gtk.Revealer();     // Background image
	private Gtk.Revealer _background_jukebox = new Gtk.Revealer();      // Background image
	private Gtk.Overlay _overlay             = new Gtk.Overlay ();
	private StationSet jukebox_station_set;      // Jukebox station set
	private SearchController _search_controller;      // Search controller
	private StationListBox _search_results;      // Search results list
	private string _pending_search_term = "";



    /* --------------------------------------------------------
    
        Public Methods

       ---------------------------------------------------------- */

    /**
     * @brief Constructs a new Display instance.
     * @param app Application context for connectivity and app-level signals.
     * @param directory The directory controller to use.
     * @param player Player controller used for playback-driven behavior.
     * @param stars Star storage service for starred-station updates.
     * @param provider Data provider for station-count metadata and genre loading.
     */
    public Display(
		Application app,
		DirectoryController directory,
		PlayerController player,
		StarStore stars,
		DataProvider.API provider
	)
    {
        Object(
            directory : directory,
            source_list : new SourceList(),
            stack : new Gtk.Stack ()
        );
        
		_app = app;
		_player = player;
		_stars = stars;
		_provider = provider;

        // Jukebox set up - get the station set and connect signals for shuffle and tape counter
        jukebox_station_set = _directory.load_random_stations(1);
        _app.events.shuffle_requested_sig.connect(() =>
        {
            if (_shuffle)
                jukebox_shuffle.begin();
        });

        _app.events.state_changed_sig.connect((station, state) =>
        {
            if (_shuffle && state == PlayerController.Is.STOPPED_ERROR)
            {
	                Timeout.add(HeaderBar.SHUFFLE_ERROR_RETRY_DELAY_MS, () =>
	                {
	                    jukebox_shuffle.begin();
	                    return Source.REMOVE;
                });
            }
        });


		var tuner = new Gtk.Image.from_icon_name (BACKGROUND_TUNER, Gtk.IconSize.INVALID);
		tuner.opacity                         = BACKGROUND_OPACITY;
		_background_tuner.transition_duration = BACKGROUND_TRANSITION_TIME_MS;
		_background_tuner.transition_type     = BACKGROUND_TRANSITION_TYPE;
		_background_tuner.reveal_child        = true;
		_background_tuner.child               = tuner;

		var jukebox = new Gtk.Image.from_icon_name (BACKGROUND_JUKEBOX, Gtk.IconSize.INVALID);
		jukebox.opacity                         = BACKGROUND_OPACITY;
		_background_jukebox.transition_duration = BACKGROUND_TRANSITION_TIME_MS;
		_background_jukebox.transition_type     = BACKGROUND_TRANSITION_TYPE;
		_background_jukebox.reveal_child        = false;
		_background_jukebox.child               = jukebox;

		var background = new Gtk.Fixed();
		background.add(_background_tuner);
		background.add(_background_jukebox);
		background.halign = Gtk.Align.CENTER;
		background.valign = Gtk.Align.CENTER;
		_overlay.add (background);


		stack.transition_type = Gtk.StackTransitionType.CROSSFADE;
		_overlay.add_overlay(stack);

        // ---------------------------------------------------------------------------

        // Set up the LHS directory structure

        _selections_category.collapsible = false;
        _selections_category.expanded = true;

        _library_category.collapsible = false;
        _library_category.expanded = false;

        _saved_searches_category.collapsible = true;
        _explore_category.collapsible = true;
        _genres_category.collapsible = true;
        _subgenres_category.collapsible = true;
        _eras_category.collapsible = true;
        _talk_category.collapsible = true;

        // Reset collapsible sections, then apply saved mask.
        _saved_searches_category.expanded = false;
        _explore_category.expanded = false;
        _genres_category.expanded = false;
        _subgenres_category.expanded = false;
        _eras_category.expanded = false;
        _talk_category.expanded = false;
        apply_category_expanded_mask (_app.settings.category_expanded_mask);

        // Persist expansion changes from the UI.
        _saved_searches_category.notify["expanded"].connect (() => update_category_expanded_mask());
        _explore_category.notify["expanded"].connect (() => update_category_expanded_mask());
        _genres_category.notify["expanded"].connect (() => update_category_expanded_mask());
        _subgenres_category.notify["expanded"].connect (() => update_category_expanded_mask());
        _eras_category.notify["expanded"].connect (() => update_category_expanded_mask());
        _talk_category.notify["expanded"].connect (() => update_category_expanded_mask());

        
        source_list.root.add (_selections_category);
        source_list.root.add (_library_category);
        source_list.root.add (_explore_category);
        source_list.root.add (_genres_category);
        source_list.root.add (_subgenres_category);
        source_list.root.add (_eras_category);
        source_list.root.add (_talk_category);

		// Ellipsize long item names so badges remain visible within the display width.
		source_list.ellipsize_mode = Pango.EllipsizeMode.END;
		source_list.item_selected.connect  ((item) =>
		// Syncs Item choice to Stack view
		{
			if (item is StationListItem)
				((StationListItem)item).populate( this );
			var selected_item   = item.get_data<string> ("stack_child");
			stack.visible_child_name    = selected_item;
		});

        // Populate the Display
		pack1 (source_list, false, false);
		pack2 (_overlay, true, false);
		set_position(200);

	} // Display


    /* --------------------------------------------------------
    
        Public

        ----------------------------------------------------------
    */

    /**
    * @brief Asynchronously shuffles to a new random station in jukebox mode
    *
    * If shuffle mode is active, selects and plays a new random station
    * from the jukebox station set.
    */
    public async void jukebox_shuffle()
    {
		if (!_shuffle)
			return;

        try 
        {
            var page = yield jukebox_station_set.next_page_async();
            if (page == null || page.size == 0)
                return;

            var station = page.to_array()[0];

			station_clicked_sig(station);
		}
		catch (SourceError e)
		{}
	} // jukebox_shuffle


	// --------------------------------------------------------
	// Source list expansion mask handling
	// --------------------------------------------------------

	private void apply_category_expanded_mask (uint mask)
	{
		_suppress_source_list_mask_write = true;
		_saved_searches_category.expanded = (mask & SOURCE_LIST_EXPANDED_SAVED_SEARCHES) != 0;
		_explore_category.expanded = (mask & SOURCE_LIST_EXPANDED_EXPLORE) != 0;
		_genres_category.expanded = (mask & SOURCE_LIST_EXPANDED_GENRES) != 0;
		_subgenres_category.expanded = (mask & SOURCE_LIST_EXPANDED_SUBGENRES) != 0;
		_eras_category.expanded = (mask & SOURCE_LIST_EXPANDED_ERAS) != 0;
		_talk_category.expanded = (mask & SOURCE_LIST_EXPANDED_TALK) != 0;
		_suppress_source_list_mask_write = false;
	} // apply_category_expanded_mask


	private void update_category_expanded_mask ()
	{
		if (_suppress_source_list_mask_write)
			return;

		uint mask = 0;
		if (_saved_searches_category.expanded)
			mask |= SOURCE_LIST_EXPANDED_SAVED_SEARCHES;
		if (_explore_category.expanded)
			mask |= SOURCE_LIST_EXPANDED_EXPLORE;
		if (_genres_category.expanded)
			mask |= SOURCE_LIST_EXPANDED_GENRES;
		if (_subgenres_category.expanded)
			mask |= SOURCE_LIST_EXPANDED_SUBGENRES;
		if (_eras_category.expanded)
			mask |= SOURCE_LIST_EXPANDED_ERAS;
		if (_talk_category.expanded)
			mask |= SOURCE_LIST_EXPANDED_TALK;

		_app.settings.persist_category_expanded_mask (mask);
	} // update_category_expanded_mask


    /**
    * @brief Updates the display state based on activation status
    * @param activate Whether to activate (true) or deactivate (false) the display
    * 
    * Manages the display's active state and performs first-time initialization
    * when needed.
    */
    public void update_state( bool activate, bool start_on_starred ) 
    {        
        if ( _active && !activate )
        /* Present Offline look */
        {
            _active = false;
            return;
        }

        if ( !_active && activate )
        // Move from not active to active
        {
            if (_first_activation)
            // One time set up - do post initialization
            {
                _first_activation = false;
                initialize.begin(() =>
                {
                    if ( start_on_starred) choose_starred_stations(); // corresponding to same call in Window
                });
            }
            _active = true;
            show_all();   
        }
    } // update_state


    /**
     * @brief Selects the starred stations view in the source list
     * 
     * Changes the current view to show the user's starred stations by selecting
     * the first child of the library category.
     */
     public void choose_starred_stations()
     {
         source_list.selected = source_list.get_first_child (_library_category);
     } // choose_star
 
 

    /* --------------------------------------------------------
    
        Private Methods

       ---------------------------------------------------------- */

    /**
    * @brief Asynchronously initializes the display components
    *
    * Sets up all categories, loads initial station data, and configures
    * signal handlers for various display components.
    */
	private async void initialize()
    {
		_directory.load (); // Initialize the DirectoryController

        /* Initialize the directory contents */

        /* ---------------------------------------------------------------------------
            Discover
        */

        var discover = StationListBoxFactory.create (
            new StationListBoxConfig (
                stack,
                source_list,
                _selections_category,
                "discover",
                "face-smile",
                _("Discover"),
                _("Stations to Discover")
            ) {
                station_set = _directory.load_random_stations(20),
                action_tooltip_text = _("Discover more stations"),
                action_icon_name = "media-playlist-shuffle-symbolic"
            }
        );
        
        discover.action_button_activated_sig.connect (() => {
            discover.item.populate( this, true );
        });


		/* ---------------------------------------------------------------------------
		    Trending
		 */
         StationListBoxFactory.create (
            new StationListBoxConfig (
                stack,
                source_list,
                _selections_category,
                "trending",
                "tuner:playlist-queue",
                _("Trending"),
                _("Trending Stations in the last 24 hours")
            ) {
                station_set = _directory.load_trending_stations(40)
            }
         );

        /* ---------------------------------------------------------------------------
            Popular
        */

        StationListBoxFactory.create (
            new StationListBoxConfig (
                stack,
                source_list,
                _selections_category,
                "popular",
                "tuner:playlist-similar",
                _("Popular"),
                _("Most listened to Stations in the last 24 hours")
            ) {
                station_set = _directory.load_popular_stations(40)
            }
        );
    

        // ---------------------------------------------------------------------------

        jukebox(_selections_category);

        // ---------------------------------------------------------------------------
        // Country-specific stations list
        
        //  var item4 = new SourceList.Item (_("Your Country"));
        //  item4.icon = new ThemedIcon ("emblem-web");
        //  ContentBox c_country;
        //  c_country = create_content_box ("my-country", item4,
        //                      _("Your Country"), null, null,
        //                      stack, source_list, true);
        //  var c_slist = new StationList ();
        //  c_slist.selection_changed.connect (handle_station_click);
        //  c_slist.favourites_changed.connect (handle_favourites_changed);

        // ---------------------------------------------------------------------------

        /* ---------------------------------------------------------------------------
            Starred
        */

        var starred = StationListBoxFactory.create (
            new StationListBoxConfig (
                stack,
                source_list,
                _library_category,
                "starred",
                "starred",
                _("Starred by You"),
                _("Starred by You") + " :"
            ) {
                station_list_hookup = this,
                stations = _directory.get_starred()
            }
        );

        // Allow drag-and-drop reordering for starred stations only.
        var starred_list = starred.content as StationList;
        if (starred_list != null)
        {
            starred_list.reorderable = true;
            starred_list.reordered.connect ((uuids) => {
                _directory.reorder_starred (uuids);
            });
        } // if

        starred.badge ( @"$(starred.item_count)\t");
        starred.parameter = @"$(starred.item_count)";
        
        starred.item_count_changed_sig.connect (( item_count ) =>
        {
            starred.badge ( @"$(starred.item_count)\t");
            starred.parameter = @"$(starred.item_count)";
        });


        // ---------------------------------------------------------------------------
        // Search Results Box
        

        _search_results = StationListBoxFactory.create (
            new StationListBoxConfig (
                stack,
                source_list,
                _library_category,
                "searched",
                "folder-saved-search",
                _("Latest Search"),
                _("Search Results")
            ) {
                action_tooltip_text = _("Save this search"),
                action_icon_name = "non-starred-symbolic"
            }
        );

		_search_results.tooltip_button.sensitive = false;
		_search_controller = new SearchController(directory,this,_search_results );
		_search_controller.search_results_ready.connect ((search_term) =>
		{
			if (_pending_search_term != "" && search_term == _pending_search_term)
			{
				stack.visible_child_name = "searched";
			}
		});

        _search_results.item_count_changed_sig.connect (( item_count, parameter ) =>
        {
            if ( parameter.length > 0 && stack.get_child_by_name (parameter) == null )  // Search names are prefixed with >
            {
                _search_results.tooltip_button.sensitive = true;
                return;
            }
            _search_results.tooltip_button.sensitive = false;
        });


        // Add saved search from star press
        _search_results.action_button_activated_sig.connect (() =>
		{
            if (_app.is_offline)
                return;
            _search_results.tooltip_button.sensitive = false;
            var new_saved_search=
            add_saved_search( _search_results.parameter, _directory.add_saved_search (_search_results.parameter));
			new_saved_search.content = _search_results.content;
			source_list.selected = source_list.get_last_child (_saved_searches_category);
		});


        // ---------------------------------------------------------------------------
        // Saved Searches


        // Add saved searches to category from Directory
        var saved_searches = _directory.load_saved_searches();
        foreach( var search_term in saved_searches.keys)
        {
           add_saved_search( search_term, saved_searches.get (search_term));
        }
        _saved_searches_category.icon = new ThemedIcon ("library-music");
        _library_category.add (_saved_searches_category);   // Added as last item of library category

        // ---------------------------------------------------------------------------

        // Explore Categories category
        // Get random categories and stations in them
        if ( _app.is_online)
        {
            uint explore = 0;
            foreach (var tag in _directory.load_random_genres(EXPLORE_CATEGORIES))
            {
                if ( Genre.in_genre (tag.name)) 
                    break;  // Predefined genre, ignore

                StationListBoxFactory.create (
                    new StationListBoxConfig (
                        stack,
                        source_list,
                        _explore_category,
                        @"$(explore++)",   // tag names can have characters that are not suitable for name
                        "tuner:playlist-symbolic",
                        tag.name,
                        tag.name
                    ) {
                        station_set = _directory.load_by_tag (tag.name)
                    }
                );
            } // foreach
        } // if

        // ---------------------------------------------------------------------------

        // Genre Boxes
        create_category_genre( stack, source_list, _genres_category, _directory,   Genre.GENRES );

        // Sub Genre Boxes
        create_category_genre( stack, source_list, _subgenres_category, _directory,   Genre.SUBGENRES );

        // Eras Boxes
        create_category_genre( stack, source_list, _eras_category,   _directory, Genre.ERAS );
    
        // Talk Boxes
        create_category_genre( stack, source_list, _talk_category, _directory,   Genre.TALK );
    
        // --------------------------------------------------------------------


        _app.events.starred_stations_changed_sig.connect ((station) =>
        /*
        * Refresh the starred stations list when a station is starred or unstarred
         */
        {
            if (_app.is_offline && _directory.get_starred ().size > 0)
                return;
                
            var _slist = StationList.with_stations (_directory.get_starred ());
			station_list_hookup(_slist);
			starred.content = _slist;
            starred.parameter = @"$(starred.item_count)";
            starred.show_all();
		});


        source_list.selected = source_list.get_first_child(_selections_category);

		show();
	} // initialize


    /* -------------------------------------------------

        Helpers

        Shortcuts to configure the source_list and stack

       -------------------------------------------------
    */

    /**
     * @brief Configures the jukebox mode for a category.
     * @param category The category to configure.
     */
    private void jukebox(SourceList.ExpandableItem category)
    {
        SourceList.Item item = new SourceList.Item(_("Jukebox"));
        item.icon = new ThemedIcon("tuner:jukebox");
        item.tooltip = (_("Double click to shuffle through %1$u stations")
                    + "\n" + _("one, every ten minutes, for %2$u days")
        ).printf (
            _provider.available_stations (),
            _provider.available_stations () / (6 * 24)
        );

        item.activated.connect(() =>
        {
                _shuffle = true;
                jukebox_shuffle.begin();
                _app.events.shuffle_mode_sig(true);
                _background_tuner.reveal_child = false;    
                _background_jukebox.reveal_child = true; 
        });

		_app.events.tape_counter_sig.connect((oldstation) =>
		{
			if (_shuffle)
				jukebox_shuffle.begin();
		});
		category.add(item);
	} // jukebox


    /**
    * @brief Hooks up signals for a StationList.
    * @param station_list The StationList to hook up.
    *
    * Configures signal handlers for station clicks and favorites changes.
    */
	internal void station_list_hookup(StationList station_list)
    {
		station_list.station_clicked_sig.connect((station) =>
		{
			station_clicked_sig(station);
            if ( _shuffle ) 
            {
                _shuffle = false;
                _app.events.shuffle_mode_sig(false);
                _background_jukebox.reveal_child = false;
                _background_tuner.reveal_child   = true;
            } // if
		});
	}  // station_list_hookup



    /**
     * Adds a saved search to the display with the specified search term and station set.
     * 
     * @param search      The search term to be saved
     * @param station_set The set of stations to associate with this search
     * @param content    Optional station list to be used as content. If null, a new list will be created
     * 
     * @return Returns a StationListBox widget containing the search results
     */
    private StationListBox add_saved_search(string search, StationSet station_set) //, StationList? content = null)//StationSet station_set)
    {
        var saved_search = StationListBoxFactory.create (
            new StationListBoxConfig (
                stack,
                source_list,
                _saved_searches_category,
                search,
                "tuner:playlist-symbolic",
                search,
                (_("Saved Search") + " :  %s").printf (search)
            ) {
                station_set = station_set,
                action_tooltip_text = _("Remove this saved search"),
                action_icon_name = "starred-symbolic"
            }
        );

        //  if ( content != null ) { 
        //      saved_search.content = content; 
        //  }

        saved_search.action_button_activated_sig.connect (() => {
            if ( _app.is_offline ) return;
            _directory.remove_saved_search (search);
            if ( _search_results.parameter == search )
                _search_results.tooltip_button.sensitive = true;
            saved_search.delist ();
        });

        return saved_search;
    } // refresh_saved_searches


	/**
	* @brief Creates genre-specific categories in the source list.
	* @param stack The stack widget.
	* @param source_list The source list widget.
	* @param category The category to add to.
	* @param directory The directory controller.
	* @param genres The array of genres.
	*/
	private void create_category_genre
        ( Gtk.Stack stack,
        SourceList source_list,
        SourceList.ExpandableItem category,
        DirectoryController directory,
        string[] genres
        )
    {
		foreach (var genre in genres )
		{
			StationListBoxFactory.create (
                new StationListBoxConfig (
                    stack,
                    source_list,
                    category,
                    genre,
                    "tuner:playlist-symbolic",
                    genre,
                    genre
                ) {
                    station_set = directory.load_by_tag (genre.down ())
                }
            );
		} // foreach
	} // create_category_genre
} // Display
