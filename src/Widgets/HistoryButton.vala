/**
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file HistoryButton.vala
 *
 * @brief HistoryButton classes
 *
 */

using Gtk;
using Gee;

using Tuner.Events;
using Tuner.Models;
using Tuner.Services;

/**
 * @class HistoryButton
 *
 * @brief A custom button with a dropdown menu displaying station and track history
 *
 * The HistoryButton class provides a button that displays a dropdown menu of stations/tracks
 * and allows for context actions such as copying the list to the clipboard or clearing
 * all items from the menu.
 *
 * Four summary tiles head the list: Tracks, Stations, Hearted and All Time. The All Time tile switches
 * the list to the hearted tracks kept across sessions (HeartedArchive), newest first with the play time and
 * date; copy, clear and the total play time then act on that list, and clearing asks first because it is
 * permanent.
 *
 * Right-clicking a row, in either list, offers a MusicBrainz search for the track in the default browser.
 * The search text is the track text with the station name, and the punctuation next to it, removed from the
 * start and end, percent-encoded. All Time rows can also be removed one at a time.
 *
 * Set G_MESSAGES_DEBUG=all to log where clicks go and what search text is built, prefixed "[history]".
 *
 * @extends Gtk.Button
 */
public class Tuner.Widgets.HistoryButton : Gtk.Button
{
	private const int MAX_VISIBLE_ROWS = 12;

	/** @brief Milliseconds between choosing a station in the list and the popover closing. */
	private const uint CLOSE_DELAY_MS = 300;

	/**
	* @signal item_station_selected_sig
	* @brief Emitted when a station is selected from the dropdown menu.
	* @param station The selected station.
	*/
	public signal void item_station_selected_sig(Station station);

	/**
	* @signal item_station_uuid_selected_sig
	* @brief Emitted when a track in the All Time list is selected. Only the station's UUID is kept with
	*        those tracks, so the receiver has to look the station up.
	* @param station_uuid The UUID of the station the track played on.
	*/
	public signal void item_station_uuid_selected_sig(string station_uuid);

	/** @brief Narrowest the history list gets, in pixels, however short the entries are. */
	private const int MIN_LIST_WIDTH_PX = 340;

	private Gtk.Popover history_popover;
	private SessionHistoryView _session_view;
	private AllTimeView _all_time_view;
	private Gtk.ScrolledWindow history_scroller;
	private HistorySummary _summary;
	private Gtk.Button copy_button;
	private Gtk.Button clear_button;
	private Gtk.Stack list_stack;
	private HeartedArchive _archive;
	private bool _showing_all_time = false;
	private Gtk.Label total_play_time_value;
	private AppEventBus _events;
	private ulong _playback_time_tick_handler_id = 0;

	/**
	* @brief Constructs a new HistoryButton with an icon.
	* @param icon_name The name of the icon to display on the button.
	* @param size The size of the icon.
	*/
	public HistoryButton.from_icon_name(History history, HeartedArchive archive, AppEventBus events, string? icon_name,  IconSize size = IconSize.BUTTON)
	{
		Object(history: history);
		_events = events;
		_archive = archive;
		var image = new Image.from_icon_name(icon_name, size);
		this.set_image(image);
		initialize();
	} // HistoryButton

	
	/**
	* @brief Constructs a new HistoryButton without an icon.
	*/
	public HistoryButton(History history, HeartedArchive archive, AppEventBus events)
	{
		Object(history: history);
		_events = events;
		_archive = archive;
		initialize();
	} // HistoryButton


	public History history { get; construct; }


	/**
	 * @brief Initialize the history popover and wire event handlers.
	 *
	 * This builds the popover UI, which creates the two lists, and starts live
	 * playback tick updates.
	 */
	private void initialize()
	{
		build_popover();
		this.clicked.connect(() => {
			if (history.entries.size > 0 || _archive.count > 0)
			{
				// Always open on the session history; All Time is one click away on the summary tile.
				set_all_time_view(false);
				refresh_history_popover();
				history_popover.popup();
			}
		});
		_archive.changed_sig.connect(() => {
			_all_time_view.mark_stale();
			if (_showing_all_time)
				_all_time_view.refresh();
			refresh_summary();
		});
		start_playback_time_tick_listener();
		refresh_summary();
	} // initialize


	/**
	 * @brief Create and configure the history popover UI.
	 *
	 * The popover contains a summary row, action buttons, total playback
	 * duration, and a scrollable list of history items.
	 */
	private void build_popover()
	{
		history_popover = new Gtk.Popover(this);
		history_popover.position = Gtk.PositionType.BOTTOM;
		history_popover.border_width = 0;
		history_popover.get_style_context().add_class("history-popover");

		var content = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
		content.margin_top = 10;
		content.margin_bottom = 10;
		content.margin_start = 10;
		content.margin_end = 10;

		_summary = new HistorySummary(history, _archive);
		_summary.all_time_clicked.connect(() => { set_all_time_view(!_showing_all_time); });
		content.pack_start(_summary, false, false, 0);

		var action_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
		action_row.margin_top = 10;
		action_row.margin_bottom = 10;
		action_row.get_style_context().add_class("history-action-row");

		copy_button = new Gtk.Button.from_icon_name("edit-copy-symbolic", IconSize.BUTTON);
		copy_button.tooltip_text = _("Copy history to clipboard");
		copy_button.clicked.connect(() => {
			copy_list_to_clipboard();
			history_popover.popdown();
		});

		clear_button = new Gtk.Button.from_icon_name("edit-clear-symbolic", IconSize.BUTTON);
		clear_button.tooltip_text = _("Clear history");
		clear_button.clicked.connect(() => {
			clear_all_items();
		});

		action_row.pack_start(copy_button, false, false, 0);
		action_row.pack_start(clear_button, false, false, 0);

		var action_spacer = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
		action_spacer.hexpand = true;
		action_row.pack_start(action_spacer, true, true, 0);

		total_play_time_value = new Gtk.Label(format_duration(history.total_played_seconds));
		total_play_time_value.width_chars = 7;
		total_play_time_value.xalign = 1.0f;
		total_play_time_value.tooltip_text = _("Total play time");
		total_play_time_value.get_style_context().add_class("history-total-time");
		action_row.pack_start(total_play_time_value, false, false, 12);

		content.pack_start(action_row, false, false, 0);

		_session_view = new SessionHistoryView(history);
		_session_view.station_selected.connect((station) => {
			item_station_selected_sig(station);
			close_popover_soon();
		});
		_session_view.content_changed.connect(() => { refresh_summary(); });

		// Diagnostics: show which level of the widget tree actually receives button presses.
		_session_view.add_events(Gdk.EventMask.BUTTON_PRESS_MASK);
		_session_view.button_press_event.connect((event) => {
			TrackListView.trace(@"history_list press: button=$(event.button) x=$(event.x) y=$(event.y)");
			return false;
		});
		history_popover.button_press_event.connect((event) => {
			TrackListView.trace(@"history_popover press: button=$(event.button) x=$(event.x) y=$(event.y)");
			return false;
		});
		history_popover.closed.connect(() => { TrackListView.trace("history_popover closed"); });


		history_scroller = new Gtk.ScrolledWindow(null, null);
		history_scroller.hscrollbar_policy = Gtk.PolicyType.NEVER;
		history_scroller.vscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
		// Width follows the widest row (station or title text), between a floor that keeps the
		// summary tiles usable and a cap of TrackListView.MAX_ROW_TEXT_CHARS characters; longer text is ellipsized.
		history_scroller.propagate_natural_width = true;
		history_scroller.min_content_width = MIN_LIST_WIDTH_PX;
		history_scroller.min_content_height = 320;
		history_scroller.max_content_height = 420;
		_all_time_view = new AllTimeView(_archive);
		_all_time_view.station_selected.connect((station_uuid) => {
			item_station_uuid_selected_sig(station_uuid);
			close_popover_soon();
		});

		// Either the session history or the All Time list is visible; the stack only sizes to the visible one.
		list_stack = new Gtk.Stack();
		list_stack.homogeneous = false;
		list_stack.add_named(_session_view, "history");
		list_stack.add_named(_all_time_view, "all-time");
		history_scroller.add(list_stack);
		content.pack_start(history_scroller, true, true, 0);

		history_popover.add(content);
		content.show_all();
		history_popover.hide();
	} // build_popover

	/**
	 * @brief Closes the popover a moment from now.
	 *
	 * This is done a moment late so that the second click of a double-click lands on the list and not on
	 * whatever is underneath it.
	 */
	private void close_popover_soon()
	{
		GLib.Timeout.add_once(CLOSE_DELAY_MS, () => { history_popover.popdown(); });
	} // close_popover_soon


	/**
	* @brief Copies the list of menu items to the clipboard.
	*/
	private void copy_list_to_clipboard()
	{
		copy_text_to_clipboard(_showing_all_time ? _archive.build_clipboard_text() : history.build_clipboard_text());
	} // copy_list_to_clipboard


	/**
	* @brief Clears all items from the dropdown menu.
	*/
	private void clear_all_items()
	{
		if (!_showing_all_time)
		{
			history.clear_preserving_last();
			return;
		}

		if (_archive.count == 0)
			return;

		// The All Time list is permanent, so confirm before wiping it.
		history_popover.popdown();
		var dialog = new Gtk.MessageDialog(app().window, Gtk.DialogFlags.MODAL, Gtk.MessageType.QUESTION,
			Gtk.ButtonsType.NONE, "%s", _("Clear the All Time list?"));
		dialog.secondary_text = _("This permanently removes all hearted tracks saved for All Time.");
		dialog.add_button(_("Cancel"), Gtk.ResponseType.CANCEL);
		dialog.add_button(_("Clear"), Gtk.ResponseType.OK);
		dialog.response.connect((response_id) => {
			if (response_id == Gtk.ResponseType.OK)
				_archive.clear();
			dialog.destroy();
		});
		dialog.present();
	} // clear_all_items


	/**
	 * @brief Switch the popover between the session history and the All Time list.
	 *
	 * Copy, clear and the total play time follow the list being shown.
	 */
	private void set_all_time_view(bool all_time)
	{
		_showing_all_time = all_time;
		list_stack.visible_child_name = all_time ? "all-time" : "history";

		_summary.set_all_time_active(all_time);

		copy_button.tooltip_text = all_time ? _("Copy All Time list to clipboard") : _("Copy history to clipboard");
		clear_button.tooltip_text = all_time ? _("Clear All Time list") : _("Clear history");
		total_play_time_value.tooltip_text = all_time ? _("Total All Time play time") : _("Total play time");

		if (all_time)
			_all_time_view.refresh();
		refresh_summary();
	} // set_all_time_view

	/**
	* @brief Appends a station-title pair to the dropdown menu.
	* @param station The station to add.
	* @param title The title associated with the station.
	*/
	public void append_station_title_pair(Station station, string title)
	{
		history.append(station, title);
	} // append_station_title_pair


	/**
	* @brief Replaces the last station-title pair if it matches the provided title.
	*
	* @param station Station associated with the last item.
	* @param title_to_match Title to match against the last item.
	* @param replacement_title Title to use when replacing.
	* @return True if the last item was replaced.
	*/
	public bool set_last_entry_hearted_if_matches(Station station, string title, bool hearted)
	{
		return history.set_last_entry_hearted_if_matches(station, title, hearted);
	} // set_last_entry_hearted_if_matches


	/**
	* @brief Returns all hearted track titles from the list.
	*
	* @return List of track titles without the heart prefix.
	*/
	public Gee.List<string> get_hearted_titles()
	{
		return history.get_hearted_titles();
	} // get_hearted_titles


	/**
	* @brief Returns all hearted history lines from the list.
	*
	* @return List of history lines without the heart prefix.
	*/
	public Gee.List<string> get_hearted_history_lines_without_hearts()
	{
		return history.get_hearted_history_lines();
	} // get_hearted_history_lines_without_hearts

	private void refresh_summary()
	{
		_summary.refresh();
		if (total_play_time_value != null)
			total_play_time_value.label = _showing_all_time
				? format_duration(_archive.total_played_seconds)
				: format_duration(history.total_played_seconds);

		bool has_entries = history.entries.size > 0 || _archive.count > 0;
		this.sensitive = has_entries;

		if (history_scroller != null)
			history_scroller.min_content_height = history.entries.size > MAX_VISIBLE_ROWS ? 420 : 320;
	} // refresh_summary


	/**
	 * @brief Refreshes history rows and summary values before showing the popover.
	 *
	 * This ensures the displayed play time is current for any active history entry
	 * as soon as the popover opens.
	 */
	private void refresh_history_popover()
	{
		refresh_summary();
		_session_view.refresh_rows();
	} // refresh_history_popover


	/**
	 * @brief Start listening for playback time ticks while the history popover is visible.
	 *
	 * The live tick listener updates the summary and any currently playing row so
	 * elapsed times stay accurate while the popover remains open.
	 */
	private void start_playback_time_tick_listener()
	{
		_playback_time_tick_handler_id = _events.playback_time_tick_sig.connect((station, total_play_seconds, station_play_seconds) =>
		{
			if (!history_popover.visible)
				return;

			refresh_summary();
			_session_view.refresh_playing_rows();
		});
	} // start_playback_time_tick_listener

} // HistoryButton
