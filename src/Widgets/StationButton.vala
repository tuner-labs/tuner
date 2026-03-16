/**
 * SPDX-FileCopyrightText: Copyright © 2020-2024 Louis Brauer <louis@brauer.family>
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

 using Tuner.Models;
 using Tuner.Widgets;

/**
 * @class StationBox
 * @brief A custom button widget representing a radio station.
 * 
 * The StationBox class extends the WelcomeButton class to create a specialized
 * button for displaying radio station information. It includes the station's
 * title, location, codec, bitrate, and favicon.
 * 
 * @extends Tuner.DisplayButton
 */
public class Tuner.Widgets.StationButton : Base.DisplayButton
{

    private const string DEFAULT_ICON_NAME = "tuner:internet-radio";

    /**
     * @property station
     * @brief The radio station represented by this StationBox.
     */
    public Station station { get; construct; }

    /**
     * @property menu
     * @brief The context menu associated with this StationBox.
     */
    public StationContextMenu menu { get; private set; }

    private ulong favicon_handler_id;

    /**
     * @brief Constructs a new StationBox instance.
     * @param station The radio station to represent.
     */
    public StationButton (Station station) 
    {
        Object (
            description: make_description (station.countrycode),
            title: make_title (station.name, station.starred, station.is_up_to_date),
            tag: make_tag (station.codec, station.bitrate),
            favicon_image: new Gtk.Image.from_icon_name (DEFAULT_ICON_NAME, Gtk.IconSize.DIALOG),
            station: station
        );

        get_style_context().add_class("station-button");
        always_show_image = true;
        can_focus = false;
        focus_on_click = false;

		station.station_star_changed_sig.connect (() =>
		{
			this.title = make_title (this.station.name, this.station.starred);
		});


        event.connect ((e) => {
            if (e.type == Gdk.EventType.BUTTON_PRESS && e.button.button == 3) {
                // Optimization:
                // Create menu on demand not on construction
                // because it is rarely used for all stations
                if (menu == null) {
                    menu = new StationContextMenu (this);
                    menu.attach_to_widget (this, null);
                    menu.show_all ();
                }

                menu.popup_at_pointer ();
                return true;
            }
            return false;
        });

        /*
            Set the button image. Connect to the flag that the Station has loaded the favicon
            and when it set, update the image. Check that if its already loaded, load now.
        */        
        favicon_handler_id = station.favicon_sig.connect(() => 
        {
            station.disconnect(favicon_handler_id);
            station.update_favicon_image.begin (_favicon_image);
        });
        if ( station.favicon_loaded() > 0 ) 
        {
            station.disconnect(favicon_handler_id);
            station.update_favicon_image.begin (_favicon_image);
        }
    } // StationButton

	/**
	* @brief Toggles reorder visuals for drag-and-drop.
	*
	* @param enabled Whether reorder visuals should be shown.
	*/
	public void set_reorder_visuals (bool enabled)
	{
		if (enabled)
			get_style_context().add_class("reorderable");
		else
			get_style_context().remove_class("reorderable");
		set_drag_handle_visible (enabled);
	}


	/**
	* @brief Updates the station button with current information from the provider.
    *
	* @param starred Whether the station is starred (favourited).
	*/
	public void update(bool starred = false)
	{
		_station = station.updated();
		station.update_favicon_image.begin (_favicon_image);
		_station.starred = starred;
		description      = make_description (station.countrycode);
		title            = make_title (station.name, station.starred, station.is_up_to_date);
		tag              = make_tag (station.codec, station.bitrate);
		app().stars.update (station); 
	} // update


	/**
	* @brief Creates a title string for the station.
	* @param title The station's title.
	* @param starred Whether the station is starred (favourited).
	* @param is_up_to_date Whether the station information is up to date.
	* @return The formatted title string.
	*/
	private static string make_title (string title, bool starred,bool is_up_to_date = true)
	{
		if (!starred)
			return title;
		if (!is_up_to_date)
			return Application.EXCLAIM_CHAR + title;
		return Application.STAR_CHAR + title;
	} // make_title


    /**
     * @brief Creates a tag string combining codec and bitrate information.
     * @param codec The station's codec.
     * @param bitrate The station's bitrate.
     * @return The formatted tag string.
     */
    private static string make_tag (string codec, int bitrate) {
        var tag = codec;
        if (bitrate > 0)
        {
            tag = tag + " " + bitrate.to_string() + "k";
        }
        return tag;
    } // make_tag


	/**
	* @brief Creates a description string based on the station's location.
	* @param location The station's location.
	* @return The formatted description string.
	*/
	private static string make_description (string? location)
	{
		if (location != null && location.length > 0)
			return _(location);
		else
			return location;
	} // make_description
} // class StationButton
