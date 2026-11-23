/**
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file AllTimeView.vala
 *
 * @brief The list of hearted tracks kept across sessions.
 */

using Tuner.Models;
using Tuner.Services;

/**
 * @class AllTimeView
 *
 * @brief Shows the hearted tracks saved for All Time, newest first, with their play time and date.
 *
 * The rows are rebuilt from the archive when they are next wanted after it has changed (see
 * mark_stale() and refresh()). Clicking a row reports its station; right-clicking offers a MusicBrainz
 * search for the track, and removing it from the archive.
 */
public class Tuner.Widgets.AllTimeView : TrackListView
{
	private HeartedArchive _archive;
	private bool _stale = true;


	/**
	 * @brief Emitted when a row is clicked.
	 *
	 * Only the station's UUID is stored with a track, so the station has to be looked up to be played.
	 *
	 * @param station_uuid The UUID of the station the track played on
	 */
	public signal void station_selected (string station_uuid);

	/**
	 * @brief Creates the list. Call refresh() to fill it.
	 */
	public AllTimeView (HeartedArchive archive)
	{
		Object ();
		_archive = archive;
	} // AllTimeView


	/**
	 * @brief Notes that the archive has changed, so the rows are out of date.
	 */
	public void mark_stale ()
	{
		_stale = true;
	} // mark_stale


	/**
	 * @brief Rebuild the rows, newest first, if the archive has changed since they were built.
	 */
	public void refresh ()
	{
		if (!_stale)
			return;

		foreach (var child in get_children ())
			remove (child);

		var tracks = _archive.tracks;
		for (int index = tracks.size - 1; index >= 0; index--)
			add (build_row (tracks[index]));

		refresh_row_styles ();
		show_all ();
		_stale = false;
	} // refresh


	/**
	 * @brief Create a row for a stored track: station, title, play time and play date.
	 */
	private Gtk.ListBoxRow build_row (ArchivedTrack track)
	{
		var row = new Gtk.ListBoxRow ();
		row.activatable = track.station_uuid != "";      // Tracks saved by older versions have no station to go to
		row.selectable = false;
		row.get_style_context ().add_class ("history-row");
		row.get_style_context ().add_class ("history-row-hearted");

		var meta_box = build_meta_box ();
		var time_label = new Gtk.Label (format_duration (track.played_seconds));
		time_label.xalign = 1.0f;
		time_label.get_style_context ().add_class ("history-play-time");
		var date_label = new Gtk.Label (track.format_played_at ());
		date_label.xalign = 1.0f;
		date_label.get_style_context ().add_class ("history-play-time");
		meta_box.pack_start (time_label, false, false, 0);
		meta_box.pack_start (date_label, false, false, 0);

		var shell = build_row_content (track.station_name, track.title, true, meta_box);
		row.add (wrap_for_context_menu (shell, (event) => {
			// All Time rows can also be deleted individually.
			var remove_item = new Gtk.MenuItem.with_label (_("Remove from All Time"));
			remove_item.activate.connect (() => {
				trace ("context menu remove from All Time");
				_archive.remove (track);
			});
			show_row_context_menu (row, MusicBrainzSearch.build_term (track.title, track.station_name), event, remove_item);
		}, () => {
			if (track.station_uuid != "")
			{
				trace (@"row clicked: station='$(track.station_name)'");
				station_selected (track.station_uuid);
			}
		}));
		row.tooltip_text = track.title;
		return row;
	} // build_row
} // AllTimeView
