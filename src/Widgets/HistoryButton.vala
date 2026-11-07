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

	/**
	* @signal item_station_selected_sig
	* @brief Emitted when a station is selected from the dropdown menu.
	* @param station The selected station.
	*/
	public signal void item_station_selected_sig(Station station);

	/** @brief Widest row text, in characters, before the popover stops growing and text is ellipsized. */
	private const int MAX_ROW_TEXT_CHARS = 48;

	/** @brief Narrowest the history list gets, in pixels, however short the entries are. */
	private const int MIN_LIST_WIDTH_PX = 340;

	private Gtk.Popover history_popover;
	private Gtk.ListBox history_list;
	private Gtk.ScrolledWindow history_scroller;
	private HistorySummary _summary;
	private Gtk.Button copy_button;
	private Gtk.Button clear_button;
	private Gtk.Stack list_stack;
	private Gtk.ListBox all_time_list;
	private HeartedArchive _archive;
	private bool _showing_all_time = false;
	private bool _all_time_list_stale = true;
	private Gtk.Label total_play_time_value;
	private Gee.HashMap<HistoryEntry, Gtk.ListBoxRow> rows_by_entry;
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
	 * This sets up the internal row cache, builds the popover UI, binds the
	 * history model signals, and starts live playback tick updates.
	 */
	private void initialize()
	{
		rows_by_entry = new Gee.HashMap<HistoryEntry, Gtk.ListBoxRow>();
		build_popover();
		this.clicked.connect(() => {
			if (history.entries.size > 0 || _archive.count > 0)
			{
				// Open on the session history, or on All Time when there is no session history yet.
				set_all_time_view(history.entries.size == 0);
				refresh_history_popover();
				history_popover.popup();
			}
		});
		_archive.changed_sig.connect(() => {
			_all_time_list_stale = true;
			if (_showing_all_time)
				refresh_all_time_list();
			refresh_summary();
		});
		bind_history();
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

		history_list = new Gtk.ListBox();
		history_list.selection_mode = Gtk.SelectionMode.NONE;
		history_list.activate_on_single_click = true;
		history_list.get_style_context().add_class("history-list");

		// Diagnostics: show which level of the widget tree actually receives button presses.
		history_list.add_events(Gdk.EventMask.BUTTON_PRESS_MASK);
		history_list.button_press_event.connect((event) => {
			trace(@"history_list press: button=$(event.button) x=$(event.x) y=$(event.y)");
			return false;
		});
		history_popover.button_press_event.connect((event) => {
			trace(@"history_popover press: button=$(event.button) x=$(event.x) y=$(event.y)");
			return false;
		});
		history_popover.closed.connect(() => { trace("history_popover closed"); });


		history_scroller = new Gtk.ScrolledWindow(null, null);
		history_scroller.hscrollbar_policy = Gtk.PolicyType.NEVER;
		history_scroller.vscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
		// Width follows the widest row (station or title text), between a floor that keeps the
		// summary tiles usable and a cap of MAX_ROW_TEXT_CHARS characters; longer text is ellipsized.
		history_scroller.propagate_natural_width = true;
		history_scroller.min_content_width = MIN_LIST_WIDTH_PX;
		history_scroller.min_content_height = 320;
		history_scroller.max_content_height = 420;
		all_time_list = new Gtk.ListBox();
		all_time_list.selection_mode = Gtk.SelectionMode.NONE;
		all_time_list.get_style_context().add_class("history-list");

		// Either the session history or the All Time list is visible; the stack only sizes to the visible one.
		list_stack = new Gtk.Stack();
		list_stack.homogeneous = false;
		list_stack.add_named(history_list, "history");
		list_stack.add_named(all_time_list, "all-time");
		history_scroller.add(list_stack);
		content.pack_start(history_scroller, true, true, 0);

		history_popover.add(content);
		content.show_all();
		history_popover.hide();
	} // build_popover

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
			refresh_all_time_list();
		refresh_summary();
	} // set_all_time_view


	/**
	 * @brief Rebuild the All Time rows, newest first.
	 */
	private void refresh_all_time_list()
	{
		if (!_all_time_list_stale)
			return;

		foreach (var child in all_time_list.get_children())
			all_time_list.remove(child);

		var tracks = _archive.tracks;
		for (int index = tracks.size - 1; index >= 0; index--)
			all_time_list.add(build_all_time_row(tracks[index]));

		int row_index = 0;
		foreach (var child in all_time_list.get_children())
		{
			if ((row_index % 2) == 1)
				child.get_style_context().add_class("history-row-alt");
			row_index++;
		}

		all_time_list.show_all();
		_all_time_list_stale = false;
	} // refresh_all_time_list


	/**
	 * @brief Create a row for a stored All Time track: station, title, play time and play date.
	 */
	private Gtk.ListBoxRow build_all_time_row(ArchivedTrack track)
	{
		var row = new Gtk.ListBoxRow();
		row.activatable = false;
		row.selectable = false;
		row.get_style_context().add_class("history-row");
		row.get_style_context().add_class("history-row-hearted");

		var shell = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 10);
		shell.margin_top = 8;
		shell.margin_bottom = 8;
		shell.margin_start = 10;
		shell.margin_end = 10;

		var text_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 3);
		text_box.hexpand = true;

		var station_label = new Gtk.Label(track.station_name);
		station_label.xalign = 0.0f;
		station_label.max_width_chars = MAX_ROW_TEXT_CHARS;
		station_label.ellipsize = Pango.EllipsizeMode.END;
		station_label.get_style_context().add_class("history-row-station");

		var title_label = new Gtk.Label(track.title);
		title_label.xalign = 0.0f;
		title_label.wrap = true;
		title_label.wrap_mode = Pango.WrapMode.WORD_CHAR;
		title_label.max_width_chars = MAX_ROW_TEXT_CHARS;
		title_label.ellipsize = Pango.EllipsizeMode.END;
		title_label.get_style_context().add_class("history-row-title");
		title_label.get_style_context().add_class("history-row-title-hearted");

		text_box.pack_start(station_label, false, false, 0);
		text_box.pack_start(title_label, false, false, 0);
		shell.pack_start(text_box, true, true, 0);

		var meta_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
		meta_box.valign = Gtk.Align.START;
		meta_box.halign = Gtk.Align.END;
		meta_box.margin_start = 8;

		var time_label = new Gtk.Label(format_duration(track.played_seconds));
		time_label.xalign = 1.0f;
		time_label.get_style_context().add_class("history-play-time");
		var date_label = new Gtk.Label(track.format_played_at());
		date_label.xalign = 1.0f;
		date_label.get_style_context().add_class("history-play-time");
		meta_box.pack_start(time_label, false, false, 0);
		meta_box.pack_start(date_label, false, false, 0);
		shell.pack_start(meta_box, false, false, 0);

		var event_box = new Gtk.EventBox();
		event_box.visible_window = false;
		event_box.above_child = true;
		event_box.add(shell);
		event_box.button_press_event.connect((event) => {
			if (event.type == Gdk.EventType.BUTTON_PRESS && event.button == Gdk.BUTTON_SECONDARY)
			{
				show_row_context_menu(row, MusicBrainzSearch.build_term(track.title, track.station_name), event, track);
				return true;
			}
			return false;
		});

		row.add(event_box);
		row.tooltip_text = track.title;
		return row;
	} // build_all_time_row


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


	/**
	 * @brief Attach history model signals to the popover UI.
	 *
	 * Listens for history changes and creates, removes, or updates rows as the
	 * underlying model changes.
	 */
	private void bind_history()
	{
		history.entry_added_sig.connect((entry) => { add_menu_item(entry); });
		history.entry_removed_sig.connect((entry) => { remove_menu_item(entry); });
		history.entry_changed_sig.connect((entry) => { update_menu_item(entry); });
		history.cleared_sig.connect(() => {
			clear_menu_items();
			refresh_summary();
		});

		foreach (var entry in history.entries)
			add_menu_item(entry);
	} // bind_history


	/**
	 * @brief Adds a menu item for the given history entry.
	 * @param entry The history entry to add.
	 */
	/**
	 * @brief Add a row for a new history entry.
	 *
	 * New entries are inserted at the top of the list so the most recent history
	 * is shown first.
	 */
	private void add_menu_item(HistoryEntry entry)
	{
		var row = build_history_row(entry);
		rows_by_entry.set(entry, row);
		history_list.insert(row, 0);
		refresh_row_styles();
		refresh_summary();
	} // add_menu_item


	/**
	 * @brief Removes the menu item for the given history entry.
	 * @param entry The history entry to remove.
	 */
	/**
	 * @brief Remove a row from the history list when an entry is deleted.
	 */
	private void remove_menu_item(HistoryEntry entry)
	{
		var row = rows_by_entry.get(entry);
		if (row == null)
			return;
		history_list.remove(row);
		rows_by_entry.unset(entry);
		refresh_row_styles();
		refresh_summary();
	} // remove_menu_item


	/**
	 * @brief Refresh the UI for an existing history entry row.
	 *
	 * This rebuilds the row contents when the entry changes, including
	 * play time, hearted state, or title updates.
	 */
	private void update_menu_item(HistoryEntry entry)
	{
		var row = rows_by_entry.get(entry);
		if (row == null)
			return;
		rebuild_history_row(row, entry);
		refresh_summary();
	} // update_menu_item


	/**
	 * @brief Remove all row widgets from the history list.
	 */
	private void clear_menu_items()
	{
		foreach (var row in rows_by_entry.values)
			history_list.remove(row);
		rows_by_entry.clear();
		refresh_row_styles();
	} // clear_menu_items


	/**
	 * @brief Create a single history row widget.
	 *
	 * Each row contains the station, title, elapsed play time, and a heart
	 * indicator when applicable.
	 */
	private Gtk.ListBoxRow build_history_row(HistoryEntry entry)
	{
		var row = new Gtk.ListBoxRow();
		row.activatable = true;
		row.selectable = false;
		row.get_style_context().add_class("history-row");
		rebuild_history_row(row, entry);
		row.activate.connect(() => {
			trace(@"row activated: station='$(entry.station.name)'");
			item_station_selected_sig(entry.station);
			history_popover.popdown();
		});
		return row;
	} // build_history_row



	/** @brief Debug-only diagnostics for the history popover (right-click search). */
	private static void trace(string message)
	{
		if (Tuner.debug_enabled())
			debug("[history] " + message);
	} // trace

	/**
	 * @brief Show the right-click menu for a history row.
	 */
	private void show_row_context_menu(Gtk.ListBoxRow row, string term, Gdk.EventButton event, ArchivedTrack? stored_track = null)
	{
		trace(@"search term -> '$term'");
		if (term == "" && stored_track == null)
			return;

		var menu = new Gtk.Menu();
		if (term != "")
		{
			var search_item = new Gtk.MenuItem.with_label(_("Search for track on MusicBrainz"));
			search_item.activate.connect(() => {
				trace("context menu item activated");
				MusicBrainzSearch.open(term, app().window);
			});
			menu.append(search_item);
		}

		// All Time rows can also be deleted individually.
		if (stored_track != null)
		{
			var remove_item = new Gtk.MenuItem.with_label(_("Remove from All Time"));
			remove_item.activate.connect(() => {
				trace("context menu remove from All Time");
				_archive.remove(stored_track);
			});
			menu.append(remove_item);
		}
		menu.show_all();
		menu.attach_to_widget(row, null);
		menu.show.connect(() => { trace("context menu shown"); });
		menu.deactivate.connect(() => { trace("context menu dismissed"); });
		trace(@"popping up context menu (popover visible=$(history_popover.visible), modal=$(history_popover.modal))");
		menu.popup_at_pointer(event);
		trace(@"popup_at_pointer returned, menu visible=$(menu.visible)");
	} // show_row_context_menu

	/**
	 * @brief Rebuild the contents of a history row from a history entry.
	 *
	 * This creates the row layout and updates the displayed metadata for the
	 * given entry each time it changes.
	 */
	private void rebuild_history_row(Gtk.ListBoxRow row, HistoryEntry entry)
	{
		var existing_child = row.get_child();
		if (existing_child != null)
			row.remove(existing_child);

		var shell = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 10);
		shell.margin_top = 8;
		shell.margin_bottom = 8;
		shell.margin_start = 10;
		shell.margin_end = 10;

		var text_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 3);
		text_box.hexpand = true;

		var station_label = new Gtk.Label(entry.station.name);
		station_label.xalign = 0.0f;
		station_label.max_width_chars = MAX_ROW_TEXT_CHARS;
		station_label.ellipsize = Pango.EllipsizeMode.END;
		station_label.get_style_context().add_class("history-row-station");

		var title_label = new Gtk.Label(entry.get_display_title());
		title_label.xalign = 0.0f;
		title_label.wrap = true;
		title_label.wrap_mode = Pango.WrapMode.WORD_CHAR;
		title_label.max_width_chars = MAX_ROW_TEXT_CHARS;
		title_label.ellipsize = Pango.EllipsizeMode.END;
		title_label.tooltip_text = entry.get_display_title();
		title_label.get_style_context().add_class("history-row-title");
		if (entry.hearted)
			title_label.get_style_context().add_class("history-row-title-hearted");

		text_box.pack_start(station_label, false, false, 0);
		text_box.pack_start(title_label, false, false, 0);
		shell.pack_start(text_box, true, true, 0);

		var meta_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
		meta_box.valign = Gtk.Align.START;
		meta_box.halign = Gtk.Align.END;
		meta_box.margin_start = 8;

		var time_label = new Gtk.Label(format_duration(entry.get_total_played_seconds()));
		time_label.width_chars = 7;
		time_label.xalign = 1.0f;
		time_label.get_style_context().add_class("history-play-time");
		meta_box.pack_start(time_label, false, false, 0);

		if (entry.hearted)
		{
			var heart_label = new Gtk.Label("♥");
			heart_label.valign = Gtk.Align.START;
			heart_label.halign = Gtk.Align.END;
			heart_label.get_style_context().add_class("history-heart-badge");
			meta_box.pack_start(heart_label, false, false, 0);
			row.get_style_context().add_class("history-row-hearted");
		}
		else
		{
			row.get_style_context().remove_class("history-row-hearted");
		}

		shell.pack_start(meta_box, false, false, 0);

		// An EventBox has its own input window above the content, so right-clicks reach it
		// reliably (plain ListBoxRows inside a popover were not delivering them).
		var event_box = new Gtk.EventBox();
		event_box.visible_window = false;
		event_box.above_child = true;
		event_box.add(shell);
		event_box.button_press_event.connect((event) => {
			trace(@"row eventbox press: button=$(event.button) type=$((int) event.type) x=$(event.x) y=$(event.y) station='$(entry.station.name)'");
			if (event.type == Gdk.EventType.BUTTON_PRESS && event.button == Gdk.BUTTON_SECONDARY)
			{
				show_row_context_menu(row, MusicBrainzSearch.build_term(entry.title, entry.station.name), event);
				return true;
			}
			return false; // left click continues on to row activation
		});

		row.add(event_box);
		row.tooltip_text = entry.get_display_title();
		row.show_all();
	} // rebuild_history_row

	/**
	 * @brief Apply alternating row styles to visible history rows.
	 */
	private void refresh_row_styles()
	{
		var children = history_list.get_children();
		int index = 0;
		foreach (var child in children)
		{
			var row = child as Gtk.ListBoxRow;
			if (row == null)
				continue;

			if ((index % 2) == 1)
				row.get_style_context().add_class("history-row-alt");
			else
				row.get_style_context().remove_class("history-row-alt");

			index++;
		}
	} // refresh_row_styles


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
		foreach (var entry in history.entries)
		{
			update_menu_item(entry);
		}
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
			foreach (var entry in history.entries)
			{
				if (entry.playing)
					update_menu_item(entry);
			}
		});
	} // start_playback_time_tick_listener

} // HistoryButton
