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

/**
 * @namespace Tuner
 * @brief Main namespace for the Tuner application
 */
namespace Tuner {

    // Fade duration used for window and image transitions (milliseconds)
    public const uint WINDOW_FADE_MS = 400;

    /**
    * @brief Available themes
    *
    */
    public enum THEME
    {
        SYSTEM,
        LIGHT,
        DARK;

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


    public static void apply_theme_name(string requested_theme)
    {

        // gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'.
        
        if ( requested_theme == THEME.LIGHT.get_name() )
        {
            debug(@"Applying theme: light");           
            Gtk.Settings.get_default().set_property("gtk-theme-name", "Adwaita");
            return;
        }

        if ( requested_theme == THEME.DARK.get_name() )
        {
            debug(@"Applying theme: dark");            
            Gtk.Settings.get_default().set_property("gtk-theme-name", "Adwaita-dark");
            return;
        }

        if ( requested_theme == THEME.SYSTEM.get_name() )
        {
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

} // namespace Tuner