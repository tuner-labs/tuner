/**
 * SPDX-FileCopyrightText: Copyright © 2026 <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file StationNoteWindow.vala
 */

using Tuner.Models;
using Tuner.Services;

/**
 * @class StationNoteWindow
 * @brief A small window to add, edit or remove the user's note on a station.
 *
 * Holds up to StarStore.NOTE_MAX_CHARS characters, with a live count. Save stores the note; saving
 * blank text removes it. Cancel or Escape closes without saving.
 *
 * @extends Gtk.Window
 */
public class Tuner.Widgets.StationNoteWindow : Gtk.Window
{
	private const int TEXT_WIDTH_PX  = 380;
	private const int TEXT_HEIGHT_PX = 160;

	private Station _station;
	private Gtk.TextView _text_view;
	private Gtk.Label _count_label;
	private bool _trim_pending = false;


	/**
	 * @brief Creates the window for a station.
	 *
	 * @param parent Window this one belongs to.
	 * @param station Station the note is for.
	 */
	public StationNoteWindow (Gtk.Window parent, Station station)
	{
		Object (
			transient_for:       parent,
			destroy_with_parent: true,
			title:               _("Station Note"),
			resizable:           false,
			window_position:     Gtk.WindowPosition.CENTER_ON_PARENT,
			type_hint:           Gdk.WindowTypeHint.DIALOG
		);

		_station = station;

		var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
		content.margin = 20;

		var name_label = new Gtk.Label (null);
		name_label.set_markup ("<b>%s</b>".printf (Markup.escape_text (_station.name)));
		name_label.xalign         = 0.0f;
		name_label.ellipsize      = Pango.EllipsizeMode.END;
		name_label.max_width_chars = 40;
		content.pack_start (name_label, false, false, 0);

		_text_view = new Gtk.TextView ();
		_text_view.wrap_mode     = Gtk.WrapMode.WORD_CHAR;
		_text_view.accepts_tab   = false;
		_text_view.left_margin   = 6;
		_text_view.right_margin  = 6;
		_text_view.top_margin    = 6;
		_text_view.bottom_margin = 6;
		_text_view.buffer.text   = app().stars.get_note (_station.stationuuid);

		var scroller = new Gtk.ScrolledWindow (null, null);
		scroller.shadow_type = Gtk.ShadowType.IN;
		scroller.hscrollbar_policy = Gtk.PolicyType.NEVER;
		scroller.set_size_request (TEXT_WIDTH_PX, TEXT_HEIGHT_PX);
		scroller.add (_text_view);
		content.pack_start (scroller, true, true, 0);

		_count_label = new Gtk.Label ("");
		_count_label.xalign = 1.0f;
		_count_label.get_style_context ().add_class ("dim-label");
		content.pack_start (_count_label, false, false, 0);

		var cancel_button = new Gtk.Button.with_label (_("Cancel"));
		cancel_button.clicked.connect (() => { close (); });

		var save_button = new Gtk.Button.with_label (_("Save"));
		save_button.get_style_context ().add_class ("suggested-action");
		save_button.clicked.connect (save_note);

		var buttons = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
		buttons.pack_end (save_button, false, false, 0);
		buttons.pack_end (cancel_button, false, false, 0);

		// Remove deletes a saved note; there is nothing to remove until one has been saved
		if (app().stars.has_note (_station.stationuuid))
		{
			var remove_button = new Gtk.Button.with_label (_("Remove Note"));
			remove_button.get_style_context ().add_class ("destructive-action");
			remove_button.clicked.connect (remove_note);
			buttons.pack_start (remove_button, false, false, 0);
		}
		content.pack_start (buttons, false, false, 0);

		add (content);

		_text_view.buffer.changed.connect (on_text_changed);
		update_count ();

		key_press_event.connect ((event) =>
		{
			if (event.keyval == Gdk.Key.Escape)
			{
				close ();
				return true;
			}
			return false;
		});

		show_all ();
		_text_view.grab_focus ();
	} // StationNoteWindow


	/**
	 * @brief Keeps the note within the limit, cutting anything typed or pasted past it.
	 */
	private void on_text_changed ()
	{
		update_count ();

		// The buffer can't be edited from inside its own changed signal, so trim when idle.
		if (_text_view.buffer.get_char_count () > StarStore.NOTE_MAX_CHARS && !_trim_pending)
		{
			_trim_pending = true;
			Idle.add (() =>
			{
				_trim_pending = false;
				var buffer = _text_view.buffer;
				if (buffer.get_char_count () > StarStore.NOTE_MAX_CHARS)
				{
					Gtk.TextIter start;
					Gtk.TextIter end;
					buffer.get_iter_at_offset (out start, StarStore.NOTE_MAX_CHARS);
					buffer.get_end_iter (out end);
					buffer.delete (ref start, ref end);
				}
				return Source.REMOVE;
			});
		}
	} // on_text_changed


	/**
	 * @brief Shows how many characters are used.
	 */
	private void update_count ()
	{
		int used = int.min (_text_view.buffer.get_char_count (), StarStore.NOTE_MAX_CHARS);
		_count_label.label = "%d / %d".printf (used, StarStore.NOTE_MAX_CHARS);
	} // update_count


	/**
	 * @brief Deletes the station's saved note and closes the window.
	 */
	private void remove_note ()
	{
		app().stars.set_note (_station.stationuuid, "");
		close ();
	} // remove_note


	/**
	 * @brief Stores the note and closes the window.
	 */
	private void save_note ()
	{
		app().stars.set_note (_station.stationuuid, _text_view.buffer.text);
		close ();
	} // save_note
} // StationNoteWindow
