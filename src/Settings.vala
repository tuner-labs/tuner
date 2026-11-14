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
    private const string SETTINGS_STARTUP_JINGLE = "startup-jingle";
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
    private const string SETTINGS_PLAY_IN_BACKGROUND = "play-in-background";
    private const string SETTINGS_INHIBIT_SLEEP = "inhibit-sleep";
    private const string SETTINGS_SAVE_ALL_TIME_HEARTED = "save-all-time-hearted";
    private const string SETTINGS_CATEGORY_EXPANDED_MASK = "category-expanded-mask";

    public bool auto_play { get; set; }
    public bool do_not_vote { get; set; }
    public string last_played_station { get; set; }
    public bool start_on_starred { get; set; }
    public bool startup_jingle { get; set; }
    public bool stream_info { get; set; }
    public bool stream_info_fast { get; set; }
    public bool stream_info_image_popup { get; set; }
    public bool stream_info_dynamic_shrink { get; set; }
    public string theme_mode { get; set; }
    public string language { get; set; }
    public double volume { get; set; }
    public bool play_restart { get; set; }
    public bool play_in_background { get; set; }
    public bool inhibit_sleep { get; set; }
    public bool save_all_time_hearted { get; set; }
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
        bind (SETTINGS_STARTUP_JINGLE, this, "startup_jingle", SettingsBindFlags.DEFAULT);
        bind (SETTINGS_STREAM_INFO, this, "stream_info", SettingsBindFlags.DEFAULT);
        bind (SETTINGS_STREAM_INFO_FAST, this, "stream_info_fast", SettingsBindFlags.DEFAULT);
        bind (SETTINGS_STREAM_INFO_IMAGE_POPUP, this, "stream_info_image_popup", SettingsBindFlags.DEFAULT);
        bind (SETTINGS_STREAM_INFO_DYNAMIC_SHRINK, this, "stream_info_dynamic_shrink", SettingsBindFlags.DEFAULT);
        bind (SETTINGS_THEME_MODE, this, "theme_mode", SettingsBindFlags.DEFAULT);
        bind (SETTINGS_LANGUAGE, this, "language", SettingsBindFlags.DEFAULT);
        bind (SETTINGS_VOLUME, this, "volume", SettingsBindFlags.DEFAULT);
        bind (SETTINGS_PLAY_RESTART, this, "play_restart", SettingsBindFlags.DEFAULT);
        bind (SETTINGS_PLAY_IN_BACKGROUND, this, "play_in_background", SettingsBindFlags.DEFAULT);
        bind (SETTINGS_INHIBIT_SLEEP, this, "inhibit_sleep", SettingsBindFlags.DEFAULT);
        bind (SETTINGS_SAVE_ALL_TIME_HEARTED, this, "save_all_time_hearted", SettingsBindFlags.DEFAULT);
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

    
    /**
     * @brief Puts the window where it was when the app last closed, and the size it was.
     *
     * The window is left centred if no position was saved.
     */
    public void configure(Gtk.Window window)
    {
        if (_pos_x != 0 && _pos_y != 0) {
            window.window_position = Gtk.WindowPosition.NONE;
            window.move(_pos_x, _pos_y);
        }
        if (_window_width > 0 && _window_height > 0) {
            window.resize(_window_width, _window_height);
        }
    } // configure


    /**
     * @brief Reads the position of the window.
     *
     * GTK reports (0,0) when the window isn't mapped yet or the frame extents haven't been updated, so
     * the underlying GDK window geometry is used then, which is more reliable on many window managers.
     * (0,0) is left as it is if neither knows, and is read as "centre" on the next launch.
     */
    private void read_window_position(Gtk.Window window)
    {
        window.get_position(out _pos_x, out _pos_y);
        if (_pos_x != 0 || _pos_y != 0)
            return;

        var gwin = window.get_window();
        if (gwin == null)
            return;

        int gx, gy, gw, gh;
        gwin.get_geometry(out gx, out gy, out gw, out gh);
        if (gx != 0 || gy != 0)
        {
            _pos_x = gx;
            _pos_y = gy;
        }
    } // read_window_position


    /**
     * @brief Reads the size of the window, from the widget allocation.
     *
     * This is more reliable than reading `window.width`/`window.height` directly. The underlying GDK
     * window geometry is used if the allocation is not known. The cached size is left as it is if
     * neither knows, which is read as "default" on the next launch.
     */
    private void read_window_size(Gtk.Window window)
    {
        int w, h;
        window.get_size(out w, out h);
        if (w <= 0 || h <= 0)
        {
            var gwin = window.get_window();
            if (gwin == null)
                return;

            int gx, gy;
            gwin.get_geometry(out gx, out gy, out w, out h);
        }

        if (w > 0 && h > 0)
        {
            _window_width = w;
            _window_height = h;
        }
    } // read_window_size


    /**
     * @brief Saves the position and size of the window, and writes the settings out.
     *
     * @param window The main window, or null if there is none (only the settings are written)
     */
    public void save(Gtk.Window? window)
    {
        if (window != null)
            save_window_geometry(window);
        sync();
    } // save


    /** @brief Saves the position and size of the window. */
    private void save_window_geometry(Gtk.Window window)
    {
        read_window_position(window);
        if (_pos_x != 0 && _pos_y != 0)
        {
            set_int(SETTINGS_POS_X, _pos_x);
            set_int(SETTINGS_POS_Y, _pos_y);
        }

        read_window_size(window);
        if (_window_width > 0 && _window_height > 0)
        {
            set_int(SETTINGS_WINDOW_WIDTH, _window_width);
            set_int(SETTINGS_WINDOW_HEIGHT, _window_height);
        }
    } // save_window_geometry

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
