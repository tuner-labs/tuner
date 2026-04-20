/**
 * SPDX-FileCopyrightText: Copyright © 2020-2024 Louis Brauer <louis@brauer.family>
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file StationContextMenu.vala
 */
 
using Tuner.Models;

/**
 * @class StationContextMenu
 * @brief A context menu for radio stations.
 *
 * This class represents a context menu that appears when interacting with a radio station.
 * It provides options such as visiting the station's website, copying the stream URL,
 * and starring/unstarring the station.
 *
 * @extends Gtk.Menu
 */
public class Tuner.Widgets.StationContextMenu : Gtk.Menu 
{
    /**
     * @property station
     * @brief The radio station associated with this context menu.
     */
    public StationButton station_button { get; construct; }
    private Station _station;

    /**
     * @brief Constructs a new StationContextMenu.
     * @param station_button The radio station for which this menu is created.
     */
    public StationContextMenu (StationButton station_button) 
    {
        Object (
            station_button: station_button
        );
    }

    /**
     * @brief Initializes the menu items and sets up event handlers.
     */
    construct {

        _station = station_button.station;

        // Name
        var name = new Gtk.MenuItem.with_label (_station.name);
        name.sensitive = false;
		append (name);
        
        if ( _station.locale() != null && _station.locale() != "")
        {
            var info = new Gtk.MenuItem.with_label (_station.locale());
            info.sensitive = false;
            append (info);
        }

		append (new Gtk.SeparatorMenuItem ());


        // ----------------------------------------------


        var popularity = new Gtk.MenuItem.with_label (_station.popularity ());
        popularity.sensitive = false;
		append (popularity);

		append (new Gtk.SeparatorMenuItem ());


        // ----------------------------------------------


        var not_up_to_date = new Gtk.MenuItem.with_label (_("Station info updated Online - View changes"));
        var make_up_to_date = new Gtk.MenuItem.with_label (_("Update Station from Online"));
        make_up_to_date.activate.connect (() =>
        {
            station_button.update(true);
            remove(not_up_to_date);
            remove(make_up_to_date);
        });

		var website = new Gtk.MenuItem.with_label (_("Visit Website"));
		if (_station.homepage != null && _station.homepage.length > 0)
		{
			website.activate.connect (on_website_handler);
		}
        website.set_tooltip_text (_station.homepage);

		var stream_url = new Gtk.MenuItem.with_label (_("Copy Stream-URI to clipboard"));
		stream_url.sensitive = true;
		stream_url.activate.connect (on_streamurl_handler);
        stream_url.set_tooltip_text (( _station.urlResolved == null || _station.urlResolved == "" ) ? _station.url : _station.urlResolved);


        // Star
        var star = new Gtk.MenuItem ();
        set_context_star (star);
        star.activate.connect (() =>
        {
            _station.toggle_starred ();
            set_context_star (star);
        }); // Context starred action


		if (!_station.is_up_to_date)
		{
			not_up_to_date.tooltip_text = _station.up_to_date_difference;
			if (!_station.is_in_index)
				make_up_to_date.sensitive = false;
			append (not_up_to_date);
			append (make_up_to_date);
			append (new Gtk.SeparatorMenuItem ());
		}
		append (website);
		append (stream_url);
        append (star);
    }


    /**
    * @brief Handles the action to open the station's website.
    */
	private void on_website_handler ()
	{
		try
		{
			Gtk.show_uri_on_window (app().window, _station.homepage, Gdk.CURRENT_TIME);
		} catch (Error e)
		{
			//warning (@"Unable to open website: $(e.message)");
			warning ((_("Unable to open website") + ": %s").printf (e.message));
		}
	}


    /**
    * @brief Handles copying the stream URL to clipboard. UrlResolved is the stream url, url can be playlists
    */
	private void on_streamurl_handler ()
	{
		Gdk.Display   display   = Gdk.Display.get_default ();
		Gtk.Clipboard clipboard = Gtk.Clipboard.get_for_display (display, Gdk.SELECTION_CLIPBOARD);
		clipboard.set_text (( _station.urlResolved == null || _station.urlResolved == "" ) ? _station.url : _station.urlResolved, -1);
	}

    /**
    * @brief Updates the star menu item's label based on the station's starred status.
    * @param item The menu item to update.
    */
	private void set_context_star (Gtk.MenuItem item)
	{
		//item.label = _station.starred ? Application.UNSTAR_CHAR + _("Unstar this station") : Application.STAR_CHAR + _("Star this station");
        item.label = _station.starred
        ? ("%s" + _("Unstar this station")).printf (Application.UNSTAR_CHAR)
        : ("%s" + _("Star this station")).printf (Application.STAR_CHAR);
    }

}
