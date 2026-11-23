/**
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file HistorySummary.vala
 *
 * @brief The row of summary tiles at the head of the history popover.
 */

using Tuner.Models;

/**
 * @class HistorySummary
 *
 * @brief Four tiles that count the session history: Tracks, Stations and Hearted, and All Time.
 *
 * The All Time tile is a button. It reports clicks with all_time_clicked and shows with
 * set_all_time_active() whether the list below it is the All Time list.
 */
public class Tuner.Widgets.HistorySummary : Gtk.Box
{
	private History _history;
	private HeartedArchive _archive;

	private Gtk.Label _plays_value;
	private Gtk.Label _changes_value;
	private Gtk.Label _hearted_value;
	private Gtk.Label _all_time_value;
	private Gtk.Button _all_time_tile;


	/**
	 * @brief Emitted when the All Time tile is clicked.
	 */
	public signal void all_time_clicked();


	/**
	 * @brief Creates the tiles. Call refresh() to fill in the counts.
	 *
	 * @param history The session history, which supplies the first three counts
	 * @param archive The hearted tracks kept across sessions, which supplies the All Time count
	 */
	public HistorySummary(History history, HeartedArchive archive)
	{
		Object(orientation: Gtk.Orientation.HORIZONTAL, spacing: 6);
		_history = history;
		_archive = archive;

		homogeneous = true;
		get_style_context().add_class("history-summary-box");

		pack_start(create_tile(_("Tracks"), out _plays_value), true, true, 0);
		pack_start(create_tile(_("Stations"), out _changes_value), true, true, 0);
		pack_start(create_tile(_("Hearted"), out _hearted_value), true, true, 0);

		// All Time is a button: it switches the list between this session and the saved hearted tracks.
		_all_time_tile = new Gtk.Button();
		_all_time_tile.relief = Gtk.ReliefStyle.NONE;
		_all_time_tile.tooltip_text = _("Hearted tracks saved for All Time");
		_all_time_tile.add(create_tile(_("All Time ♥"), out _all_time_value));
		_all_time_tile.clicked.connect(() => { all_time_clicked(); });
		pack_start(_all_time_tile, true, true, 0);
	} // HistorySummary


	/**
	 * @brief Updates the four counts from the history and the archive.
	 */
	public void refresh()
	{
		_plays_value.label = _history.entries.size.to_string();
		_changes_value.label = _history.station_change_count.to_string();
		_hearted_value.label = _history.hearted_track_count.to_string();
		_all_time_value.label = _archive.count.to_string();
	} // refresh


	/**
	 * @brief Marks the All Time tile as the one being shown, or not.
	 */
	public void set_all_time_active(bool active)
	{
		var style = _all_time_tile.get_style_context();
		if (active)
			style.add_class("history-summary-tile-active");
		else
			style.remove_class("history-summary-tile-active");
	} // set_all_time_active


	/**
	 * @brief Create a summary tile: a number above a localized caption.
	 *
	 * @param label_text The caption
	 * @param value_label The label that shows the number, for the caller to update
	 */
	private Gtk.Widget create_tile(string label_text, out Gtk.Label value_label)
	{
		var tile = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);
		tile.hexpand = true;
		tile.margin_top = 4;
		tile.margin_bottom = 4;
		tile.margin_start = 6;
		tile.margin_end = 6;
		tile.get_style_context().add_class("history-summary-tile");

		value_label = new Gtk.Label("0");
		value_label.xalign = 0.5f;
		value_label.get_style_context().add_class("history-summary-value");

		var caption_label = new Gtk.Label(label_text);
		caption_label.xalign = 0.5f;
		caption_label.get_style_context().add_class("history-summary-caption");

		tile.pack_start(value_label, false, false, 0);
		tile.pack_start(caption_label, false, false, 0);
		return tile;
	} // create_tile
} // HistorySummary
