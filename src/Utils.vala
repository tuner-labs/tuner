/**
 * SPDX-FileCopyrightText: Copyright © 2026 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file Utils.vala
 *
 * @brief Utility functions for the Tuner radio application
 */

 using GLib;
 using Tuner.Models;
 using Tuner.Ext;

/**
 * @namespace Tuner
 * @brief Main namespace for the Tuner application
 */
namespace Tuner {

    // Fade duration used for window and image transitions (milliseconds)
    public const uint WINDOW_FADE_MS = 400;

    /**
     * @brief Build the app-wide User-Agent string.
     */
    public static string user_agent ()
    {
        return @"$(Application.APP_ID)/$(Application.APP_VERSION)";
    } // user_agent


    private static int _debug_state = -1;      // -1 unknown, 0 off, 1 on

    /**
     * @brief Whether debug logging is switched on (`G_MESSAGES_DEBUG` is set).
     *
     * Vala builds `debug(@"...")` strings before `debug()` can decide to drop them.
     * On hot paths (every HTTP request, every tick) guard the call with this so the
     * string is only built when someone is going to read it:
     * `if (Tuner.debug_enabled ()) debug(@"...");`
     */
    public static bool debug_enabled ()
    {
        if (_debug_state < 0)
        {
            var domains = Environment.get_variable ("G_MESSAGES_DEBUG");
            _debug_state = (domains != null && domains != "") ? 1 : 0;
        }
        return _debug_state == 1;
    } // debug_enabled

    /**
    * @brief Available themes
    *
    */
    public enum THEME
    {
        SYSTEM,
        LIGHT,
        DARK;

        /**
         * @brief The theme's name as used in settings: "system", "light" or "dark".
         */
        public unowned string get_name ()
        {
            switch (this) {
                case SYSTEM:
                    return "system";

                case LIGHT:
                    return "light";

                case DARK:
                    return "dark";

                default:
                    assert_not_reached();
            }
        }
    } // THEME


    /**
    * @brief Applies the given theme to the app
    *
    * @return The Application instance
    */
    public static void apply_theme(THEME requested_theme)
    {
        apply_theme_name( requested_theme.get_name() );
    } // apply_theme


    /**
     * @brief Applies a theme by name.
     *
     * "light" sets Adwaita, "dark" sets Adwaita-dark, "system" restores the system theme.
     *
     * @param requested_theme A THEME name, as returned by THEME.get_name().
     */
    public static void apply_theme_name(string requested_theme)
    {

        // gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'.
        
        if ( requested_theme == THEME.LIGHT.get_name() )
        {
            if (Tuner.debug_enabled ())
                debug(@"Applying theme: light");
            Gtk.Settings.get_default().set_property("gtk-theme-name", "Adwaita");
            return;
        }

        if ( requested_theme == THEME.DARK.get_name() )
        {
            if (Tuner.debug_enabled ())
                debug(@"Applying theme: dark");
            Gtk.Settings.get_default().set_property("gtk-theme-name", "Adwaita-dark");
            return;
        }

        if ( requested_theme == THEME.SYSTEM.get_name() )
        {
            if (Tuner.debug_enabled ())
                debug(@"System theme X: $(Application.SYSTEM_THEME())");
            Gtk.Settings.get_default().set_property("gtk-theme-name", Application.SYSTEM_THEME());
            return;
        }
        assert_not_reached();
    } // apply_theme


    /**
    * @brief Send the calling method for a nap
    *
    * @param interval the time to nap
    * @param priority priority of checking nap is over
    */
    public static async void nap (uint interval) {
        Timeout.add (interval, () => {
            nap.callback ();
            return Source.REMOVE;
        }, Priority.LOW);
        yield;
    } // nap


    /**
    * @brief Asynchronously transitions the image with a fade effect.
    * 
    * @param {Gtk.Image} image - The image to transition.
    * @param {uint} duration_ms - Duration of the fade effect in milliseconds.
    * @param {Closure} callback - Optional callback function to execute after fading.
    */
    public static async void fade_image(Gtk.Image image, uint duration_ms, bool fading_in) 
    {
        double step = 0.05; // Adjust opacity in 5% increments
        uint interval = (uint) (duration_ms / (1.0 / step)); // Interval based on duration

        while ( ( !fading_in && image.opacity != 0 ) || (fading_in && image.opacity != 1) ) 
        {      
            double op = image.opacity + (fading_in ? step : -step); 
            image.opacity = op.clamp(0, 1); 
            yield nap (interval);
        }
    } // fade_image


    /**
     * @brief Fades a widget in from transparent, easing in and out, driven by the frame clock.
     *
     * The widget is left fully opaque when it finishes.
     *
     * @param target Widget to fade in; it is made transparent first.
     * @param duration_ms Length of the fade in milliseconds.
     */
    public static void fade_in_widget(Gtk.Widget target, uint duration_ms)
    {
        target.opacity = 0.0;
        int64 began = -1;
        target.add_tick_callback ((widget, clock) =>
        {
            var now = clock.get_frame_time ();
            if (began < 0)
                began = now;

            double t = (double)(now - began) / (double)(duration_ms * 1000);
            if (t >= 1.0)
            {
                widget.opacity = 1.0;
                return Source.REMOVE;
            }
            widget.opacity = t * t * (3.0 - 2.0 * t);     // smoothstep
            return Source.CONTINUE;
        });
    } // fade_in_widget


    /**
     * Fade the entire top level window by adjusting its `opacity` property.
     */
    public static async void fade_window(Gtk.Window window, uint duration_ms, bool fading_in)
    {
        double step = 0.05;
        uint interval = (uint) (duration_ms / (1.0 / step));

        while (( !fading_in && window.opacity != 0 ) || (fading_in && window.opacity != 1))
        {
            double op = window.opacity + (fading_in ? step : -step);
            window.opacity = op.clamp(0, 1);
            yield nap(interval);
        }
    } // fade_window


    /**
     * @brief Percent-encodes text for use in a URI query.
     *
     * Everything except the unreserved characters (letters, digits, - . _ ~) is encoded, so any
     * text, including spaces, quotes, brackets, backslashes and non-ASCII characters, makes a valid
     * URI. Without this such text produced an invalid URI and a libsoup "soup_uri_is_valid" critical.
     *
     * @param text The text to encode.
     * @param keep Characters to leave as they are, for example a separator the receiving API
     *             understands. Empty by default: nothing extra is kept.
     * @return The percent-encoded text.
     */
    public static string encode_text( string text, string keep = "" )
    {
        return Uri.escape_string (text, keep, false);
    } // encode_text


    /**
     * Safely strips whitespace from a string, handling null and empty strings.
     * @param text The string to strip.
     * @return The stripped string or an empty string if input is null or empty.
     */
    public static unowned string safestrip( string? text )
    {
        if ( text == null ) return "";
        if ( text.length == 0 ) return "";
        return text._strip();
    } // safestrip


    /**
     * @brief Create a stream player for the given URL.
     *
     * Centralizes the selection of the concrete StreamPlayer implementation.
     *
     * @param stream_url Stream URL to play.
     * @return A StreamPlayer instance for the requested URL.
     */
    public static StreamPlayer create_stream_player (string stream_url)
    {
        return new GstStreamPlayer (stream_url);
    } // create_stream_player


    /**
     * @brief Play a file URI through the configured stream backend.
     *
     * Centralizes one-shot playback mapping so `StreamPlayer` remains backend-agnostic.
     *
     * @param file_uri URI to play.
     * @param volume Playback volume between 0.0 and 1.0.
     * @param on_finished Optional callback fired on EOS/ERROR.
     * @return Backend playback handle, or null when setup failed.
     */
    public static GLib.Object? play_stream_file (string file_uri, double volume, owned StreamPlayer.FilePlaybackFinished? on_finished = null)
    {
        return GstStreamPlayer.play_file_backend (file_uri, volume, (owned) on_finished);
    } // play_stream_file

} // namespace Tuner
