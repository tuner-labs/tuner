/**
 * SPDX-FileCopyrightText: Copyright © 2020-2024 Louis Brauer <louis@brauer.family>
 * SPDX-FileCopyrightText: Copyright © 2024-2026 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file Application.vala
 * @brief Contains the main Application class for the Tuner application
 *
 */

/**
 *
 * @brief Tuner application settings management.
 */
public class Tuner.Settings : GLib.Settings 
{  
    private const string SETTINGS_AUTO_PLAY = "auto-play";
    private const string SETTINGS_DO_NOT_VOTE = "do-not-vote";
    private const string SETTINGS_LAST_PLAYED_STATION = "last-played-station";
    private const string SETTINGS_POS_X = "pos-x";
    private const string SETTINGS_POS_Y = "pos-y";
    private const string SETTINGS_START_ON_STARRED = "start-on-starred";
    private const string SETTINGS_STREAM_INFO = "stream-info";
    private const string SETTINGS_STREAM_INFO_FAST = "stream-info-fast";
    private const string SETTINGS_STREAM_INFO_IMAGE_POPUP = "stream-info-image-popup";
    private const string SETTINGS_STREAM_INFO_DYNAMIC_SHRINK = "stream-info-dynamic-shrink";
    private const string SETTINGS_THEME_MODE = "theme-mode";
    private const string SETTINGS_LANGUAGE = "language";
    private const string SETTINGS_VOLUME = "volume";
    private const string SETTINGS_WINDOW_HEIGHT = "window-height";
    private const string SETTINGS_WINDOW_WIDTH = "window-width";
    private const string SETTINGS_PLAY_RESTART = "play-restart";
    private const string SETTINGS_CATEGORY_EXPANDED_MASK = "category-expanded-mask";

    public bool auto_play { get; set; }
    public bool do_not_vote { get; set; }
    public string last_played_station { get; set; }
    public bool start_on_starred { get; set; }
    public bool stream_info { get; set; }
    public bool stream_info_fast { get; set; }
    public bool stream_info_image_popup { get; set; }
    public bool stream_info_dynamic_shrink { get; set; }
    public string theme_mode { get; set; }
    public string language { get; set; }
    public double volume { get; set; }
    public bool play_restart { get; set; }
    public uint category_expanded_mask { get; set; }

    private int _pos_x;
    private int _pos_y;
    private int _window_height;
    private int _window_width;

    /** 
    * @brief Constructor for the Settings class
    *
    * This constructor initializes the Settings object by calling the parent constructor with the appropriate schema ID.
    * It then loads the settings values from the GSettings backend and assigns them to the corresponding properties of the Settings class. 
    *
    * Settings keyfile file path .var/app/app id/config/glib-2.0/settings/keyfile
    */
    public Settings() 
    {
       Object(
            schema_id : Application.APP_ID
       );

        // Keep simple properties synchronized with GSettings both ways.
        bind (SETTINGS_AUTO_PLAY, this, "auto_play", SettingsBindFlags.DEFAULT);
        bind (SETTINGS_DO_NOT_VOTE, this, "do_not_vote", SettingsBindFlags.DEFAULT);
        bind (SETTINGS_LAST_PLAYED_STATION, this, "last_played_station", SettingsBindFlags.DEFAULT);
        bind (SETTINGS_START_ON_STARRED, this, "start_on_starred", SettingsBindFlags.DEFAULT);
        bind (SETTINGS_STREAM_INFO, this, "stream_info", SettingsBindFlags.DEFAULT);
        bind (SETTINGS_STREAM_INFO_FAST, this, "stream_info_fast", SettingsBindFlags.DEFAULT);
        bind (SETTINGS_STREAM_INFO_IMAGE_POPUP, this, "stream_info_image_popup", SettingsBindFlags.DEFAULT);
        bind (SETTINGS_STREAM_INFO_DYNAMIC_SHRINK, this, "stream_info_dynamic_shrink", SettingsBindFlags.DEFAULT);
        bind (SETTINGS_THEME_MODE, this, "theme_mode", SettingsBindFlags.DEFAULT);
        bind (SETTINGS_LANGUAGE, this, "language", SettingsBindFlags.DEFAULT);
        bind (SETTINGS_VOLUME, this, "volume", SettingsBindFlags.DEFAULT);
        bind (SETTINGS_PLAY_RESTART, this, "play_restart", SettingsBindFlags.DEFAULT);
        bind (SETTINGS_CATEGORY_EXPANDED_MASK, this, "category_expanded_mask", SettingsBindFlags.DEFAULT);

        _pos_x = get_int(SETTINGS_POS_X);
        _pos_y = get_int(SETTINGS_POS_Y);
        _window_height = get_int(SETTINGS_WINDOW_HEIGHT);
        _window_width = get_int(SETTINGS_WINDOW_WIDTH);

        // Debug hooks to verify category mask tracking in both directions.
        changed.connect ((key) =>
        {
            if (key == SETTINGS_CATEGORY_EXPANDED_MASK) 
            {
                debug (
                    "Settings changed from backend: %s=%u",
                    SETTINGS_CATEGORY_EXPANDED_MASK,
                    get_uint (SETTINGS_CATEGORY_EXPANDED_MASK)
                );
            } // if
        });

        notify["category-expanded-mask"].connect (() =>
        {
            debug (
                "Settings property updated: category_expanded_mask=%u",
                category_expanded_mask
            );
        });

    } // Settings

    
    /** */
    public void configure()
    {        
        if (_pos_x != 0 && _pos_y != 0) {
            app().window.window_position = Gtk.WindowPosition.NONE;
            app().window.move(_pos_x, _pos_y);
        }
        // else, leave as CENTER
        if (_window_width > 0 && _window_height > 0) {
            app().window.resize(_window_width, _window_height);
        }
        app().player.volume = _volume;     
         
    } // configure


    /** */
    public void save()
    {
        app().window.get_position(out _pos_x, out _pos_y);

        /* If GTK reports (0,0) it's possible the window isn't mapped or the
         * toolkit hasn't updated the frame extents yet. Fall back to the
         * underlying GDK window geometry which is more reliable for the
         * top level position on many window managers. */
        if (_pos_x == 0 && _pos_y == 0) {
            var gwin = app().window.get_window();
            if (gwin != null) 
            {
                int gx = 0; int gy = 0; int gw = 0; int gh = 0;
                gwin.get_geometry(out gx, out gy, out gw, out gh);
                if (gx != 0 || gy != 0) 
                {
                    _pos_x = gx;
                    _pos_y = gy;
                } // else, leave as (0,0) which will be interpreted as "center" on next launch
            } // else, leave as (0,0) which will be interpreted as "center" on next launch
        } // else, use the (0,0) position which will be interpreted as "center" on next launch

        if ( _pos_x !=0 && _pos_y != 0 )
        {
            set_int(SETTINGS_POS_X, _pos_x);
            set_int(SETTINGS_POS_Y, _pos_y);
        }

        // Refresh cached window size from the widget allocation; fall back
        // to the underlying GDK window geometry if needed. This is more
        // reliable than reading `window.width`/`window.height` directly.
        int w = 0;
        int h = 0;
        app().window.get_size(out w, out h);
        if (w > 0 && h > 0) {
            _window_width = w;
            _window_height = h;
            set_int(SETTINGS_WINDOW_WIDTH, _window_width);
            set_int(SETTINGS_WINDOW_HEIGHT, _window_height);
        } // if
        else 
        {
            var gwin = app().window.get_window();
                if (gwin != null) {
                    int gx = 0; int gy = 0; int gw = 0; int gh = 0;
                    gwin.get_geometry(out gx, out gy, out gw, out gh);
                if (gw > 0 && gh > 0) {
                    _window_width = gw;
                    _window_height = gh;
                    set_int(SETTINGS_WINDOW_WIDTH, _window_width);
                    set_int(SETTINGS_WINDOW_HEIGHT, _window_height);
                } // 
            } // else, leave as is which will be interpreted as "default" on next launch
        } // else, use the (0,0) position which will be interpreted as "default" on next launch

        sync();
    } // save

    /**
     * @brief Persist the source list expansion mask immediately.
     *
     * @param mask Bitmask representing expanded source list sections.
     */
    public void persist_category_expanded_mask (uint mask)
    {
        category_expanded_mask = mask;
        debug (
            "Persisted category_expanded_mask=%u",
            category_expanded_mask
        );
    } // persist_category_expanded_mask

} // Tuner.Settings
