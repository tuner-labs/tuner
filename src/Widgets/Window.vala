/**
 * SPDX-FileCopyrightText: Copyright © 2020-2024 Louis Brauer <louis@brauer.family>
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file Window.vala
 *
 * @brief Defines the main application window for the Tuner application.
 *
 * This file contains the Window class, which is responsible for creating and
 * managing the main application window. It handles the major layout, user interface
 * elements, and interactions with other non-display components of the application.
 *
 * The Window class inherits from Gtk.ApplicationWindow and implements various
 * features such as a header bar, main display and player controls.
 * It also manages application settings and handles user actions like playback
 * control, station selection, and theme adjustments.
 *
 * @see Tuner.Widgets.Application
 * @see Tuner.Widgets.PlayerController
 * @see Tuner.Widgets.DirectoryController
 * @see Tuner.Widgets.HeaderBar
 * @see Tuner.Widgets.Display
 */


using Gee;
using Tuner.Controllers;
using Tuner.Ext;
using Tuner.Models;

/**
 * The main application window for the Tuner app.
 * 
 * This class extends Gtk.ApplicationWindow and serves as the primary container
 * for all other widgets and functionality in the Tuner application.
 *
 * Window consists of the Header (title) and Display (main window)
 */
public class Tuner.Widgets.Window : Gtk.ApplicationWindow
{

    /* Public */

	public const string WINDOW_NAME                 = "Tuner";
	public const string ACTION_PREFIX               = "win.";
	public const string ACTION_PAUSE                = "action_pause";
	public const string ACTION_QUIT                 = "action_quit";
	public const string ACTION_HIDE                 = "action_hide";
	public const string ACTION_ABOUT                = "action_about";
	public const string ACTION_DISABLE_TRACKING     = "action_disable_tracking";
	public const string ACTION_ENABLE_AUTOPLAY      = "action_enable_autoplay";
	public const string ACTION_ENABLE_PLAY_RESTART  = "action_enable_play_restart";
	public const string ACTION_START_ON_STARRED     = "action_starred_start";
	public const string ACTION_STREAM_INFO          = "action_stream_info";
	public const string ACTION_STREAM_INFO_FAST     = "action_stream_info_fast";
	public const string ACTION_STREAM_INFO_IMAGE_POPUP = "action_stream_info_image_popup";


	public Settings settings { get; construct; }
	public PlayerController player_ctrl { get; construct; }
	public DirectoryController directory { get; construct; }

    public bool active { get; private set; } // Window is active
    public int width { get; private set; }
    public int height { get; private set; }


    /* Private */   

	private const string NOTIFICATION_PLAYING_BACKGROUND   = _("Playing in background");
	private const string NOTIFICATION_CLICK_RESUME         = _("Click here to resume window. To quit Tuner, pause playback and close the window.");
	private const string NOTIFICATION_APP_RESUME_WINDOW    = "app.resume-window";
	private const string NOTIFICATION_APP_PLAYING_CONTINUE = "continue-playing";

	private const int RANDOM_CATEGORIES = 5;

	private const int GEOMETRY_MIN_HEIGHT = 440;
	private const int GEOMETRY_MIN_WIDTH  = 600;

	private delegate bool SettingBoolGetter();
	private delegate void SettingBoolSetter(bool value);
	private delegate void ToggleBoolCallback(bool value);

	private const ActionEntry[] ACTION_ENTRIES = {
		{ ACTION_PAUSE,                 on_toggle_playback                         },
		{ ACTION_QUIT,                  on_action_quit                             },
		{ ACTION_ABOUT,                 on_action_about                            },
		{ ACTION_DISABLE_TRACKING,      on_action_disable_tracking, null, "false"  },
		{ ACTION_ENABLE_AUTOPLAY,       on_action_enable_autoplay, null, "false"   },
		{ ACTION_ENABLE_PLAY_RESTART,   on_action_enable_play_restart, null, "false" },
		{ ACTION_START_ON_STARRED,      on_action_start_on_starred, null, "false"  },
		{ ACTION_STREAM_INFO,           on_action_stream_info, null, "true"        },
		{ ACTION_STREAM_INFO_FAST,      on_action_stream_info_fast, null, "false"  },
		{ ACTION_STREAM_INFO_IMAGE_POPUP, on_action_stream_info_image_popup, null, "false" },
	};

    /*
        Assets
    */

	private TitleBox _title;
	private Display _display;
	private MetadataImagePopup _metadata_image_popup;
    private bool _start_on_starred = false;

	private signal void refresh_saved_searches_sig (bool add, string search_text);



    /**
     * @brief Constructs a new Window instance.
     *
     * @param app The Application instance.
     * @param player The PlayerController instance.
     */
    public Window (Application app, PlayerController player, Settings settings, DirectoryController directory ) 
    {
        Object (
            application: app,
            player_ctrl: player,
            settings: settings,
            directory: directory
        );

        add_widgets();
        check_online_status();

        if ( settings.start_on_starred ) choose_starred_stations();  // Start on starred  

        show_all ();

        Idle.add(() => {
            settings.configure();

            // Test-only sizing: override persisted size after settings are applied.
            //this.resize(900, 600);  // FIXME Comment out
			// Test Only

            /* Start with the window invisible and fade it in so restarts
             * have a matching fade-in to the fade-out used on shutdown. */
            this.opacity = 0.0;
            Tuner.fade_window.begin(this, Tuner.WINDOW_FADE_MS, true, () => { });
            return false;
        });

		application.set_accels_for_action (ACTION_PREFIX + ACTION_PAUSE, {"<Control>5"});
		application.set_accels_for_action (ACTION_PREFIX + ACTION_QUIT, {"<Control>q"});
		application.set_accels_for_action (ACTION_PREFIX + ACTION_QUIT, {"<Control>w"});
	} // Window


    /* 
        Construct 
    */
	construct 
    { 
        set_icon_name(Application.APP_ID);
        add_action_entries (ACTION_ENTRIES, this);
        set_title (WINDOW_NAME);
        window_position = Gtk.WindowPosition.CENTER;
        set_geometry_hints (
                null, 
                Gdk.Geometry() 
                {
                    min_height = GEOMETRY_MIN_HEIGHT, min_width = GEOMETRY_MIN_WIDTH
                }, 
                Gdk.WindowHints.MIN_SIZE
            );
		sync_action_states_from_settings();

               
        /*
            Setup
        */

        delete_event.connect (e => {
            return before_destroy ();
        });


        /*
            Online checks & behavior

            Keep in mind that network availability is noisy
        */
        // Window state responds to app-level connectivity events.
        app().events.connectivity_changed_sig.connect((is_online) => {
            check_online_status();
        });
    } // construct


    /**
     * Selects and displays the user's starred (favorite) radio stations.
     * 
     * This method handles the process of showing the user's favorite stations
     * in the station list view. It filters and displays only the stations that
     * have been marked as favorites by the user.
     */
	public void choose_starred_stations()
	{
        _start_on_starred = true;
		if (_active)
			_display.choose_starred_stations();
	} // choose_star


    /**
        Add widgets after Window creation
    */
	    private void add_widgets()
	    {
	        var app_ref = (Application)application;

	        /*
	            Headerbar hookups
	        */
			_metadata_image_popup = new MetadataImagePopup(this);
			_metadata_image_popup.set_enabled(settings.stream_info_image_popup);

			_title = new TitleBox(app_ref, this, player_ctrl, app_ref.provider);

			_title.search_has_focus_sig.connect (() => 
			// Show searched stack when cursor hits search text area
			{
					_display.on_search_focused();
			});

			_title.searching_for_sig.connect ( (text) => 
			// process the searched text, stripping it, and sensitizing the save 
			// search star depending on if the search is already saved
			{
					_display.on_search_requested(text);
			});

			set_titlebar (_title);		
			//set_titlebar (_headerbar);

	        /*
	            Display
	        */
	        _display = new Display(app_ref, directory, player_ctrl, app_ref.stars, app_ref.provider);  
	        _display.station_clicked_sig.connect (handle_play_station);  // Station clicked -> change station     
	        add (_display);

	    } // add_widgets


    /* --------------------------------------------------------
    
        Methods

        ----------------------------------------------------------
    */

	    // ----------------------------------------------------------------------
	    //
	    // Actions
	    //
	    // ----------------------------------------------------------------------

	/**
	 * @brief Synchronizes all window action states from persisted settings.
	 *
	 * This keeps toggle action state in sync with the values used by model buttons
	 * and other action-bound widgets when the window is constructed.
	 */
	private void sync_action_states_from_settings()
	{
		change_action_state (ACTION_DISABLE_TRACKING, settings.do_not_vote);
		change_action_state (ACTION_ENABLE_AUTOPLAY, settings.auto_play);
		change_action_state (ACTION_ENABLE_PLAY_RESTART, settings.play_restart);
		change_action_state (ACTION_START_ON_STARRED, settings.start_on_starred);
		change_action_state (ACTION_STREAM_INFO, settings.stream_info);
		change_action_state (ACTION_STREAM_INFO_FAST, settings.stream_info_fast);
		change_action_state (ACTION_STREAM_INFO_IMAGE_POPUP, settings.stream_info_image_popup);
	}


	/**
	 * @brief Toggles a boolean setting and mirrors it to the action state.
	 *
	 * @param action Action whose state should be updated.
	 * @param debug_name Identifier included in debug output.
	 * @param getter Callback that reads the current setting value.
	 * @param setter Callback that persists the new setting value.
	 * @param on_changed Optional callback invoked with the new value.
	 */
	private void toggle_setting_action(
		SimpleAction action,
		string debug_name,
		SettingBoolGetter getter,
		SettingBoolSetter setter,
		ToggleBoolCallback? on_changed = null
	) {
		bool enabled = !getter();
		setter(enabled);
		action.set_state(enabled);

		if (on_changed != null)
			on_changed(enabled);

		debug (@"$debug_name: $(enabled ? "enabled" : "disabled")");
	}


    /**
     * @brief Handles the quit action.
     */
    private void on_action_quit () 
    {
        close ();
    } // on_action_quit


    /**
     * @brief Handles the about action.
     */
    private void on_action_about () 
    {
        var dialog = new AboutDialog (this);
        dialog.present ();
    } // on_action_about


    /**
     * @brief Toggles playback state.
     */
    public void on_toggle_playback() 
    {
        info (_("Stop Playback requested"));
        player_ctrl.play_pause ();
    } // on_toggle_playback


    /**
     * @brief Handles the disable tracking action.
     * @param action The SimpleAction that triggered this method.
     * @param parameter The parameter passed with the action (unused).
     */
    public void on_action_disable_tracking (SimpleAction action, Variant? parameter) 
    {
		toggle_setting_action(
			action,
			"on_action_disable_tracking",
			() => { return settings.do_not_vote; },
			(value) => { settings.do_not_vote = value; }
		);
    } // on_action_disable_tracking


    /**
     * @brief Handles the enable autoplay action.
     * @param action The SimpleAction that triggered this method.
     * @param parameter The parameter passed with the action (unused).
     */
     public void on_action_enable_autoplay (SimpleAction action, Variant? parameter) 
     {
		toggle_setting_action(
			action,
			"on_action_enable_autoplay",
			() => { return settings.auto_play; },
			(value) => { settings.auto_play = value; }
		);
    } // on_action_enable_autoplay


    /**
     * @brief Handles the enable play-restart action.
     * @param action The SimpleAction that triggered this method.
     * @param parameter The parameter passed with the action (unused).
     */
     public void on_action_enable_play_restart (SimpleAction action, Variant? parameter) 
     {
		toggle_setting_action(
			action,
			"on_action_enable_play_restart",
			() => { return settings.play_restart; },
			(value) => { settings.play_restart = value; }
		);
    } // on_action_enable_play_restart


    /**
     * @brief Handles the start-on-starred action.
     * @param action The SimpleAction that triggered this method.
     * @param parameter The parameter passed with the action (unused).
     */
     public void on_action_start_on_starred (SimpleAction action, Variant? parameter) 
     {
		toggle_setting_action(
			action,
			"on_action_start_on_starred",
			() => { return settings.start_on_starred; },
			(value) => { settings.start_on_starred = value; }
		);
    } // on_action_start_on_starred


	/**
	 * @brief Handles stream metadata display preference changes.
	 *
	 * @param action The SimpleAction that triggered this method.
	 * @param parameter The parameter passed with the action (unused).
	 */
    public void on_action_stream_info (SimpleAction action, Variant? parameter) 
    {
		toggle_setting_action(
			action,
			"on_action_stream_info",
			() => { return settings.stream_info; },
			(value) => { settings.stream_info = value; },
			(value) => { _title.stream_info(value); }
		);
    } // on_action_enable_stream_info


	/**
	 * @brief Handles stream metadata fast-cycle preference changes.
	 *
	 * @param action The SimpleAction that triggered this method.
	 * @param parameter The parameter passed with the action (unused).
	 */
    public void on_action_stream_info_fast (SimpleAction action, Variant? parameter) 
    {
		toggle_setting_action(
			action,
			"on_action_stream_info_fast",
			() => { return settings.stream_info_fast; },
			(value) => { settings.stream_info_fast = value; },
			(value) => { _title.stream_info_fast(value); }
		);
    } // on_action_stream_info_fast

	/**
	 * @brief Handles stream metadata image popup preference changes.
	 *
	 * @param action The SimpleAction that triggered this method.
	 * @param parameter The parameter passed with the action (unused).
	 */
	public void on_action_stream_info_image_popup (SimpleAction action, Variant? parameter)
	{
		toggle_setting_action(
			action,
			"on_action_stream_info_image_popup",
			() => { return settings.stream_info_image_popup; },
			(value) => { settings.stream_info_image_popup = value; },
			(value) => { _metadata_image_popup.set_enabled(value); }
		);
	} // on_action_stream_info_image_popup



    // ----------------------------------------------------------------------
    //
    // Handlers
    //
    // ----------------------------------------------------------------------


	/**
	* @brief Handles a station selection and plays the station
	* @param station The selected station.
	*/
	public void handle_play_station (Station station)
	{
		if ( app().is_offline || !_title.update_playing_station(station) )
			return;                                                                                          // Online and not already changing station

        player_ctrl.station = station;
        _settings.last_played_station = station.stationuuid;
        _directory.count_station_click (station);

        set_title (WINDOW_NAME+": "+station.name);
    } // handle_station_click


    // ----------------------------------------------------------------------
    //
    // State management
    //
    // ----------------------------------------------------------------------

	/**
	* @brief Performs cleanup actions before the window is destroyed.
	* @return true if the window should be hidden instead of destroyed, false otherwise.
	*/
    public bool before_destroy ()
    {
        get_size (out _width, out _height); // Echo ending dimensions so Settings can pick them up
        _settings.save ();

        if (player_ctrl.player_state == PlayerInterface.State.PLAYING) {
            hide_on_delete();
            var notification = new GLib.Notification(NOTIFICATION_PLAYING_BACKGROUND);
            notification.set_body(NOTIFICATION_CLICK_RESUME);
            notification.set_default_action(NOTIFICATION_APP_RESUME_WINDOW);
            app().send_notification(NOTIFICATION_APP_PLAYING_CONTINUE, notification);
            return true;
        }

		prompt_save_hearted_tracks();

        return false;
    } // before_destroy

	private void prompt_save_hearted_tracks()
	{
		var hearted_titles = _title.get_hearted_titles();
		if (hearted_titles.size == 0)
			return;

		var dialog = new Gtk.MessageDialog(
			this,
			Gtk.DialogFlags.MODAL,
			Gtk.MessageType.QUESTION,
			Gtk.ButtonsType.NONE,
			_("Save hearted tracks to a file?")
		);
		dialog.add_button(_("_Don't Save"), Gtk.ResponseType.CANCEL);
		dialog.add_button(_("_Save"), Gtk.ResponseType.ACCEPT);

		var response = dialog.run();
		dialog.destroy();
		if (response != Gtk.ResponseType.ACCEPT)
			return;

		var save_dialog = new Gtk.FileChooserDialog(
			_("Save File"),
			this,
			Gtk.FileChooserAction.SAVE,
			_("_Cancel"), Gtk.ResponseType.CANCEL,
			_("_Save"), Gtk.ResponseType.ACCEPT
		);
		save_dialog.set_current_name("tuner-hearted-" + (new DateTime.now_local().format("%Y-%m-%d")) + ".txt");

		if (save_dialog.run() == Gtk.ResponseType.ACCEPT)
		{
			var save_path = save_dialog.get_filename();
			if (save_path != null)
			{
				var builder = new StringBuilder();
				var history_lines = _title.get_hearted_history_lines_without_hearts();
				foreach (var line in history_lines)
					builder.append(line).append("\n");
				try {
					GLib.FileUtils.set_contents(save_path, builder.str);
				} catch (Error e) {
					warning(@"Failed to save hearted tracks: $(e.message)");
				}
			}
		}
		save_dialog.destroy();
	}
    

	/**
	* @brief Checks changes in online state and updates the app accordingly
	*
	*/
	private void check_online_status()
	{
		if (active && app().is_offline)
			apply_offline_ui_state();

		if (!active && app().is_online)
			apply_online_ui_state();
	        _display.update_state (active, _start_on_starred );
	    } // check_online_status


	/**
	 * @brief Applies UI state for offline mode.
	 *
	 * Disables focus acceptance and marks the window as inactive so dependent
	 * widgets render their offline state.
	 */
	private void apply_offline_ui_state()
	{
		this.accept_focus = false;
		active            = false;
	}


	/**
	 * @brief Applies UI state for online mode.
	 *
	 * Re-enables focus acceptance and marks the window active so dependent
	 * widgets render their interactive state.
	 */
	private void apply_online_ui_state()
	{
		this.accept_focus = true;
		active            = true;
	}
} // Window
