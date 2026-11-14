/**
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file SessionHistoryView.vala
 *
 * @brief The list of tracks played in this session.
 */

using Tuner.Models;
using Tuner.Services;

/**
 * @class SessionHistoryView
 *
 * @brief Shows the session history, newest first, and keeps its rows in step with the History model.
 *
 * A row is added, removed or rebuilt as the model's entries come, go or change. Clicking a row reports
 * its station; right-clicking offers a MusicBrainz search for the track.
 */
public class Tuner.Widgets.SessionHistoryView : TrackListView
{
	private History _history;
	private Gee.HashMap<HistoryEntry, Gtk.ListBoxRow> _rows = new Gee.HashMap<HistoryEntry, Gtk.ListBoxRow> ();


	/**
	 * @brief Emitted when a row is clicked.
	 *
	 * @param station The station the track played on
	 */
	public signal void station_selected (Station station);

	/**
	 * @brief Emitted when the rows change, because the figures that sum them up may have changed.
	 */
	public signal void content_changed ();


	/**
	 * @brief Creates the list, with a row for each entry the history already has.
	 */
	public SessionHistoryView (History history)
	{
		Object ();
		_history = history;

		_history.entry_added_sig.connect ((entry) => { add_row (entry); });
		_history.entry_removed_sig.connect ((entry) => { remove_row (entry); });
		_history.entry_changed_sig.connect ((entry) => { update_row (entry); });
		_history.cleared_sig.connect (() => { clear_rows (); });

		foreach (var entry in _history.entries)
			add_row (entry);

		var empty = new Gtk.Label (_("No tracks yet this session. Click All Time ♥ above to see your hearted tracks."));
		empty.wrap        = true;
		empty.max_width_chars = 32;
		empty.margin      = 24;
		empty.sensitive   = false;
		empty.show ();
		set_placeholder (empty);
	} // SessionHistoryView


	/**
	 * @brief Rebuilds every row, so that the displayed play times are current.
	 */
	public void refresh_rows ()
	{
		foreach (var entry in _history.entries)
			rebuild_row_for (entry);
	} // refresh_rows


	/**
	 * @brief Rebuilds the rows of the entries that are playing, so that their play times keep up.
	 */
	public void refresh_playing_rows ()
	{
		foreach (var entry in _history.entries)
		{
			if (entry.playing)
				rebuild_row_for (entry);
		}
	} // refresh_playing_rows


	/**
	 * @brief Add a row for a new history entry, at the top so that the newest is shown first.
	 */
	private void add_row (HistoryEntry entry)
	{
		var row = build_row (entry);
		_rows.set (entry, row);
		insert (row, 0);
		refresh_row_styles ();
		content_changed ();
	} // add_row


	/**
	 * @brief Remove the row of an entry that has been deleted.
	 */
	private void remove_row (HistoryEntry entry)
	{
		var row = _rows.get (entry);
		if (row == null)
			return;

		remove (row);
		_rows.unset (entry);
		refresh_row_styles ();
		content_changed ();
	} // remove_row


	/**
	 * @brief Rebuild the row of an entry that has changed: its play time, hearted state or title.
	 */
	private void update_row (HistoryEntry entry)
	{
		if (rebuild_row_for (entry))
			content_changed ();
	} // update_row


	/**
	 * @brief Rebuild the row of an entry.
	 *
	 * @return false if the entry has no row
	 */
	private bool rebuild_row_for (HistoryEntry entry)
	{
		var row = _rows.get (entry);
		if (row == null)
			return false;

		rebuild_row (row, entry);
		return true;
	} // rebuild_row_for


	/**
	 * @brief Remove all rows.
	 */
	private void clear_rows ()
	{
		foreach (var row in _rows.values)
			remove (row);
		_rows.clear ();
		refresh_row_styles ();
		content_changed ();
	} // clear_rows


	/**
	 * @brief Create the row for an entry.
	 */
	private Gtk.ListBoxRow build_row (HistoryEntry entry)
	{
		var row = new Gtk.ListBoxRow ();
		row.activatable = true;
		row.selectable = false;
		row.get_style_context ().add_class ("history-row");
		rebuild_row (row, entry);
		return row;
	} // build_row


	/**
	 * @brief Rebuild the contents of a row from its entry: station, title, play time and a heart if hearted.
	 *
	 * Done each time the entry changes.
	 */
	private void rebuild_row (Gtk.ListBoxRow row, HistoryEntry entry)
	{
		var existing_child = row.get_child ();
		if (existing_child != null)
			row.remove (existing_child);

		var meta_box = build_meta_box ();

		var time_label = new Gtk.Label (format_duration (entry.get_total_played_seconds ()));
		time_label.width_chars = 7;
		time_label.xalign = 1.0f;
		time_label.get_style_context ().add_class ("history-play-time");
		meta_box.pack_start (time_label, false, false, 0);

		if (entry.hearted)
		{
			var heart_label = new Gtk.Label ("♥");
			heart_label.valign = Gtk.Align.START;
			heart_label.halign = Gtk.Align.END;
			heart_label.get_style_context ().add_class ("history-heart-badge");
			meta_box.pack_start (heart_label, false, false, 0);
			row.get_style_context ().add_class ("history-row-hearted");
		}
		else
		{
			row.get_style_context ().remove_class ("history-row-hearted");
		}

		var shell = build_row_content (entry.station.name, entry.get_display_title (), entry.hearted, meta_box);
		row.add (wrap_for_context_menu (shell, (event) => {
			show_row_context_menu (row, MusicBrainzSearch.build_term (entry.title, entry.station.name), event);
		}, () => {
			trace (@"row clicked: station='$(entry.station.name)'");
			station_selected (entry.station);
		}));
		row.tooltip_text = entry.get_display_title ();
		row.show_all ();
	} // rebuild_row
} // SessionHistoryView
