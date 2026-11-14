/**
 * SPDX-FileCopyrightText: Copyright © 2020-2024 Louis Brauer <louis@brauer.family>
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file HeaderBar.vala
 *
 * @brief HeaderBar classes
 *
 */

using Gtk;
using Tuner.Controllers;
using Tuner.Ext;
using Tuner.Models;
using Gee;
using Tuner.Services;

/**
 * @class Tuner.HeaderBar
 *
 * @brief Custom header bar that centrally displays station info and
 * packs app controls either side.
 *
 * This class extends Gtk.HeaderBar to create a specialized header bar
 * with play/pause controls, volume control, station information display,
 * search button, and preferences menu.
 *
 * @extends HeaderBar
 */
public class Tuner.Widgets.HeaderBar : Gtk.HeaderBar
{

    /* Constants    */

    // Default icon name for stations without a custom favicon
    private const string DEFAULT_ICON_NAME = "tuner:internet-radio-symbolic";

	// Reveal animation delay in milliseconds
	private const uint REVEAL_DELAY = 400u;
	public const uint STATION_CHANGE_SETTLE_DELAY_MS = 1200u;
	public const uint SHUFFLE_ERROR_RETRY_DELAY_MS = 1500u;

	private static Image STAR   = new Image.from_icon_name ("starred", IconSize.LARGE_TOOLBAR);
	private static Image UNSTAR = new Image.from_icon_name ("non-starred", IconSize.LARGE_TOOLBAR);


    /* Public */


    // Public properties

    // Signals
    public signal void search_toggle_sig ();


    /*
        Private 
    */

	protected static Image FAVICON_IMAGE = new Image.from_icon_name (DEFAULT_ICON_NAME, IconSize.DIALOG);


	/*
		main display assets
	*/
	private Base.TunerStatus _tuner_status;
	private Button _star_button = new Button.from_icon_name (
		"non-starred",
		IconSize.LARGE_TOOLBAR
		);
	private PlayButton _play_button  = new PlayButton ();
	private MenuButton _prefs_button = new MenuButton ();
	private Button _search_button = new Button.from_icon_name ("system-search-symbolic", IconSize.LARGE_TOOLBAR);
	private HistoryButton _history_button;
	private Button _heart_button = new Button();

	/*
		secondary display assets
	*/

    // data and state variables

	private Station _station;
	private Station _last_metadata_station;
	private string _last_metadata_title = "";
	private uint _station_update_in_progress = 0u;       // Guard concurrent updates with an atomic flag
	private bool _station_locked       = false;
	private ulong _station_handler_id  = 0;
	private Application _app;
	private Window _window;
	private PlayerController _player;
	private DataProvider.API _provider;

    private VolumeButton _volume_button = new VolumeButton();
    
	private PlayingStationInfo _playing_station_info;

	/** @property {bool} starred - Station starred. */
	private bool _starred = false;
	private bool starred {
		get { return _starred; }
		set {
			_starred = value;
			if (!_starred)
			{
				_star_button.image = UNSTAR;
			}
			else
			{
				_star_button.image = STAR;
			}
		}
	} // starred


    /**
     * @brief Construct block for initializing the header bar components.
     *
     * This method sets up all the UI elements of the header bar, including
     * station info display, play button, preferences button, search entry,
     * star button, and volume button.
     *
     * @param app Application context for connectivity and app-level events.
     * @param window Parent window that owns this header bar.
     * @param player Player controller used for playback state and volume.
     * @param provider Data provider used for provider statistics tooltip text.
     */
    public HeaderBar(Application app, Window window, PlayerController player, DataProvider.API provider)
    {
        Object();
		_app = app;
		_window = window;
		_player = player;
		_provider = provider;

		get_style_context ().add_class ("header-bar");

        /*
            LHS Controls
        */        

        // Tuner Status icon
		_tuner_status =new Base.TunerStatus(app, window, provider);

		
		// Volume
		_volume_button.set_valign(Align.CENTER);
		_volume_button.value_changed.connect ((value) => {
			_player.volume = value;
		});
		_app.events.volume_changed_sig.connect((value) => {
			_volume_button.value =  value;
		});


		// Star button
		_star_button.valign       = Align.CENTER;
		_star_button.sensitive    = true;
		_star_button.tooltip_text = _("Star this station");
		_star_button.clicked.connect (() => 
		{
			if (_station == null)
				return;			
			starred = _station.toggle_starred();
		});


		//
		// Create and configure play button
		//
		_play_button.valign      = Align.CENTER;
		_play_button.action_name = Window.ACTION_PREFIX + Window.ACTION_PAUSE; // Toggles player state

       
        /*
            RHS Controls
        */     

		// Search button
		_search_button.valign = Align.CENTER;
		_search_button.tooltip_text = _("Search for Stations");
		_search_button.clicked.connect (() => {
			search_toggle_sig();
		});

		// Preferences button
		_prefs_button.image  = new Image.from_icon_name ("open-menu", IconSize.LARGE_TOOLBAR);
		_prefs_button.valign = Align.CENTER;
		_prefs_button.tooltip_text = _("Preferences");
		_prefs_button.popover      = new PreferencesPopover();

		_history_button = new HistoryButton.from_icon_name(_app.history, _app.all_time, _app.events, "mark-location-symbolic", IconSize.LARGE_TOOLBAR);
		_history_button.valign       = Align.CENTER;
		_history_button.tooltip_text = _("History");

		_heart_button.image = new Image.from_icon_name ("emblem-favorite-symbolic", IconSize.LARGE_TOOLBAR);
		_heart_button.valign = Align.CENTER;
		_heart_button.tooltip_text = _("Heart current track in history");
		_heart_button.sensitive = false;
		_heart_button.clicked.connect(() =>
		{
			if (_last_metadata_station == null || _last_metadata_title == "")
				return;

			var next_hearted_state = !_app.history.is_last_entry_hearted_for(_last_metadata_station, _last_metadata_title);
			if (!_history_button.set_last_entry_hearted_if_matches(_last_metadata_station, _last_metadata_title, next_hearted_state))
			{
				_history_button.append_station_title_pair(_last_metadata_station, _last_metadata_title);
				_history_button.set_last_entry_hearted_if_matches(_last_metadata_station, _last_metadata_title, next_hearted_state);
			}

			set_heart_favorited(next_hearted_state);
		});

       /*
            Layout
        */

       // pack LHS
        //pack_start (_tuner);
        pack_start (_tuner_status );
        pack_start (_volume_button);
        pack_start (_star_button);
        pack_start (_play_button);
		pack_start (_heart_button);

	    _playing_station_info = new PlayingStationInfo(window, _player);
        custom_title = _playing_station_info; // Station display

		// pack RHS
		pack_end (_prefs_button);
		pack_end (_history_button);
		pack_end (_search_button);

		show_close_button = true;


		/*
		    Tuner icon and online/offline behavior
		 */
		// HeaderBar reacts to app-level connectivity changes for visual state updates.
		_app.events.connection_state_changed_sig.connect((state) =>
		{
			update_controls_state();
		});

		_app.events.player_state_changed_sig.connect ((station, state) =>
		{
			_app.history.sync_play_state(station, state);
			update_controls_state();
		});

	    update_controls_state();

		_playing_station_info.info_changed_completed_sig.connect(() =>
		// _player_info is going to signal when it has completed and the lock can be released
		{
			if (!_station_locked)
				return;
			AtomicUint.set (ref _station_update_in_progress, 0u);
			_station_locked = false;
		});


		_app.events.playback_metadata_changed_sig.connect ((station, metadata) =>
		{
			_history_button.append_station_title_pair(station, metadata.title);
			_app.history.sync_play_state(station, _player.player_state);
			_last_metadata_station = station;
			_last_metadata_title = metadata.title != null ? metadata.title : "";
			_heart_button.sensitive = _last_metadata_title != "";
			set_heart_favorited(_app.history.is_last_entry_hearted_for(_last_metadata_station, _last_metadata_title));
		});

		_history_button.item_station_selected_sig.connect((station) =>
		{
			window.handle_play_station(station);
		});

		_history_button.item_station_uuid_selected_sig.connect((station_uuid) =>
		{
			play_station_by_uuid.begin(station_uuid);
		});

	} // HeaderBar

	/**
	 * @brief Looks a station up by its UUID and plays it.
	 *
	 * Used for the All Time list, which keeps only the UUID of each track's station.
	 */
	private async void play_station_by_uuid(string station_uuid)
	{
		// Already playing it (a looked-up Station is a different object, so handle_play_station would not notice)
		if (_station != null && _station.stationuuid == station_uuid && _player.player_state != StreamPlayer.State.STOPPED_ERROR)
			return;

		var uuids = new Gee.ArrayList<string>();
		uuids.add(station_uuid);

		foreach (var station in yield _app.directory.get_stations_by_uuid_async(uuids))
		{
			_window.handle_play_station(station);
			return;
		}
		warning(@"The station $(station_uuid) was not found, so it cannot be played");
	} // play_station_by_uuid

	private void set_heart_favorited(bool favorited)
	{
		var ctx = _heart_button.get_style_context();
		if (favorited)
			ctx.add_class("heart-favorited");
		else
			ctx.remove_class("heart-favorited");
	} // set_heart_favorited

	/**
	 * @brief Titles hearted this session, from the history button.
	 */
	public Gee.List<string> get_hearted_titles()
	{
		return _history_button.get_hearted_titles();
	}

	/**
	 * @brief Hearted history lines without the heart markers, from the history button.
	 */
	public Gee.List<string> get_hearted_history_lines_without_hearts()
	{
		return _history_button.get_hearted_history_lines_without_hearts();
	} // get_hearted_history_lines_without_hearts


    /* 
        Public 
    */


	/**
	* @brief Update the header bar with information from a new station.
	*
	* Requires a lock so that too many clicks do not cause a race condition
	*
	* @param station The new station to display information for.
	*/
	public bool update_playing_station(Station station)
	{
		if ( _app.is_offline || ( _station != null && _station == station && _player.player_state != StreamPlayer.State.STOPPED_ERROR ) )
			return false;

		if (AtomicUint.compare_and_exchange (ref _station_update_in_progress, 0u, 1u))
		// Guard while changing the station to ensure single threading.
		// Guard is released when the info is updated on emit of info_changed_completed_sig
			{
				_station_locked       = true;
				//_player_info.metadata = STREAM_METADATA;
				_playing_station_info.queue_station_transition (station);

				Idle.add (() =>
				          // Initiate the fade out on a non-UI thread
			{

				if (_station_handler_id > 0)
				// Disconnect the old station starred handler
				{
					_station.disconnect(_station_handler_id);
					_station_handler_id = 0;
				}

				_playing_station_info.change_station.begin(station, () =>
				{
					_station            = station;
					starred             = _station.starred;
					_station_handler_id = _station.station_star_changed_sig.connect((starred) => 
					{
						this.starred = starred;
					});
				});

				return Source.REMOVE;
			},Priority.HIGH_IDLE);

			return true;
		} // if
		return false;
	} // update_playing_station


	/**
	* @brief Override of the realize method from Widget for an initial animation
	*
	* Called when the widget is being realized (created and prepared for display).
	* This happens before the widget is actually shown on screen.
	*/
	public override void realize()
	{
		base.realize();

		_playing_station_info.transition_type = RevealerTransitionType.SLIDE_UP; // Optional: add animation
		_playing_station_info.set_transition_duration(REVEAL_DELAY*3);

		// Use Timeout to delay the reveal animation
		Timeout.add(REVEAL_DELAY*3, () => {
			_playing_station_info.set_reveal_child(true);
			return Source.REMOVE;
		});
	} // realize


    /**
     */
    public void stream_info(bool show)
    {
        _playing_station_info.title_label.show_metadata = show;        
    } // stream_info


    /**
     * @brief Sets fast cycling of the stream metadata in the title label.
     */
    public void stream_info_fast(bool fast)
    {
        _playing_station_info.title_label.metadata_fast_cycle = fast;          
    } // stream_info_fast


    /**
     * @brief Enables or disables dynamic shrinking of the playing-station info.
     */
    public void stream_info_dynamic_shrink(bool enabled)
    {
        _playing_station_info.set_dynamic_shrink(enabled);
    } // stream_info_dynamic_shrink


	/*
		Private
	*/
	
	/**
	* @brief Checks and sets per the online status
	*
	* Desensitize when off-line
	*/
	private void update_controls_state()
	{
		// The online look needs the network and a radio-browser server that has answered
		bool is_playing_now = _player.player_state == StreamPlayer.State.PLAYING
			|| _player.player_state == StreamPlayer.State.BUFFERING;

		if (_app.connection.state != Events.ConnectionState.READY)
		{
			_playing_station_info.favicon_image.opacity = 0.5;
			_tuner_status.online               = false;
			_star_button.sensitive             = false;
			_play_button.sensitive             = is_playing_now;
			_play_button.opacity               = is_playing_now ? 1.0 : 0.5;
			_volume_button.sensitive           = false;
			_history_button.sensitive             = true;
			_search_button.sensitive           = false;

		}
		else
		// Online - restore full functionality
		{
			_playing_station_info.favicon_image.opacity = 1.0;
			_tuner_status.online               = true;
			_star_button.sensitive             = true;
			_play_button.sensitive             = true;
			_play_button.opacity               = 1.0;
			_volume_button.sensitive           = true;
			_history_button.sensitive             = true;
			_search_button.sensitive           = true;
		}
	} // update_controls_state
} // Tuner.HeaderBar
