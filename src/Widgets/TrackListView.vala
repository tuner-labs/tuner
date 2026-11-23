/**
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file TrackListView.vala
 *
 * @brief What the lists in the history popover have in common.
 */

using Tuner.Services;

/**
 * @class TrackListView
 *
 * @brief A list of played tracks: striped rows, and a right-click menu that searches for the track.
 *
 * The session history (SessionHistoryView) and the All Time list (AllTimeView) are both lists of
 * station and track rows that look alike and answer a right-click the same way. This class holds
 * that, and the subclasses decide which rows there are and what else the menu offers.
 */
public abstract class Tuner.Widgets.TrackListView : Gtk.ListBox
{
	/** @brief Widest row text, in characters, before text is ellipsized. */
	protected const int MAX_ROW_TEXT_CHARS = 48;

	/**
	 * @brief Called when a row is right-clicked.
	 *
	 * @param event The click, which positions the menu
	 */
	public delegate void RowMenuRequest (Gdk.EventButton event);

	/**
	 * @brief Called when a row is clicked with the primary button.
	 */
	public delegate void RowClickRequest ();


	construct
	{
		selection_mode = Gtk.SelectionMode.NONE;
		activate_on_single_click = true;
		get_style_context ().add_class ("history-list");
	}


	/** @brief Debug-only diagnostics for the history popover (right-click search). */
	public static void trace (string message)
	{
		if (Tuner.debug_enabled ())
			debug ("[history] " + message);
	} // trace


	/**
	 * @brief Apply alternating row styles to the rows.
	 */
	protected void refresh_row_styles ()
	{
		int index = 0;
		foreach (var child in get_children ())
		{
			var row = child as Gtk.ListBoxRow;
			if (row == null)
				continue;

			if ((index % 2) == 1)
				row.get_style_context ().add_class ("history-row-alt");
			else
				row.get_style_context ().remove_class ("history-row-alt");

			index++;
		}
	} // refresh_row_styles


	/**
	 * @brief Creates the box that holds the figures on the right of a row; the caller fills it.
	 */
	protected Gtk.Box build_meta_box ()
	{
		var meta_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
		meta_box.valign = Gtk.Align.START;
		meta_box.halign = Gtk.Align.END;
		meta_box.margin_start = 8;
		return meta_box;
	} // build_meta_box


	/**
	 * @brief Lays out a row: the station name above the track title, and the meta box on the right.
	 *
	 * @param station_name The station that played the track
	 * @param title The track title
	 * @param hearted Whether the title is shown as hearted
	 * @param meta The figures on the right, from build_meta_box()
	 */
	protected Gtk.Box build_row_content (string station_name, string title, bool hearted, Gtk.Widget meta)
	{
		var shell = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
		shell.margin_top = 8;
		shell.margin_bottom = 8;
		shell.margin_start = 10;
		shell.margin_end = 10;

		var text_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 3);
		text_box.hexpand = true;

		var station_label = new Gtk.Label (station_name);
		station_label.xalign = 0.0f;
		station_label.max_width_chars = MAX_ROW_TEXT_CHARS;
		station_label.ellipsize = Pango.EllipsizeMode.END;
		station_label.get_style_context ().add_class ("history-row-station");

		var title_label = new Gtk.Label (title);
		title_label.xalign = 0.0f;
		title_label.wrap = true;
		title_label.wrap_mode = Pango.WrapMode.WORD_CHAR;
		title_label.max_width_chars = MAX_ROW_TEXT_CHARS;
		title_label.ellipsize = Pango.EllipsizeMode.END;
		title_label.tooltip_text = title;
		title_label.get_style_context ().add_class ("history-row-title");
		if (hearted)
			title_label.get_style_context ().add_class ("history-row-title-hearted");

		text_box.pack_start (station_label, false, false, 0);
		text_box.pack_start (title_label, false, false, 0);
		shell.pack_start (text_box, true, true, 0);
		shell.pack_start (meta, false, false, 0);
		return shell;
	} // build_row_content


	/**
	 * @brief Wraps the content of a row so that a right-click on it can be answered.
	 *
	 * An EventBox has its own input window above the content, so right-clicks reach it reliably (plain
	 * ListBoxRows inside a popover were not delivering them). Other clicks continue on to the row.
	 *
	 * The primary button is answered here too, rather than left to the list's row activation: the
	 * click is seen by this EventBox for certain. It answers the first click of a double-click only.
	 *
	 * @param content The row content
	 * @param request What to do on a right-click
	 * @param on_click What to do on a click with the primary button, or null for nothing
	 */
	protected Gtk.EventBox wrap_for_context_menu (Gtk.Widget content, owned RowMenuRequest request, owned RowClickRequest? on_click = null)
	{
		var event_box = new Gtk.EventBox ();
		event_box.visible_window = false;
		event_box.above_child = true;
		event_box.add (content);
		event_box.button_press_event.connect ((event) => {
			trace (@"row eventbox press: button=$(event.button) type=$((int) event.type) x=$(event.x) y=$(event.y)");
			if (event.type == Gdk.EventType.BUTTON_PRESS && event.button == Gdk.BUTTON_SECONDARY)
			{
				request (event);
				return true;
			}
			if (on_click != null && event.type == Gdk.EventType.BUTTON_PRESS && event.button == Gdk.BUTTON_PRIMARY)
			{
				on_click ();
				return true;
			}
			return false;
		});
		return event_box;
	} // wrap_for_context_menu


	/**
	 * @brief Show the right-click menu for a row.
	 *
	 * @param row The row that was clicked
	 * @param term The text to search MusicBrainz for; the search is not offered if it is empty
	 * @param event The click, which positions the menu
	 * @param extra An item of the subclass's own to add to the menu, or null
	 */
	protected void show_row_context_menu (Gtk.ListBoxRow row, string term, Gdk.EventButton event, Gtk.MenuItem? extra = null)
	{
		trace (@"search term -> '$term'");
		if (term == "" && extra == null)
			return;

		var menu = new Gtk.Menu ();
		if (term != "")
		{
			var search_item = new Gtk.MenuItem.with_label (_("Search for track on MusicBrainz"));
			search_item.activate.connect (() => {
				trace ("context menu item activated");
				MusicBrainzSearch.open (term, app ().window);
			});
			menu.append (search_item);
		}

		if (extra != null)
			menu.append (extra);

		menu.show_all ();
		menu.attach_to_widget (row, null);
		menu.show.connect (() => { trace ("context menu shown"); });
		menu.deactivate.connect (() => { trace ("context menu dismissed"); });
		menu.popup_at_pointer (event);
		trace (@"popup_at_pointer returned, menu visible=$(menu.visible)");
	} // show_row_context_menu
} // TrackListView
