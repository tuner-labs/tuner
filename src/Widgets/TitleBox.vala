/**
 * SPDX-FileCopyrightText: Copyright © 2026 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file TitleBox.vala
 *
 * @brief TitleBox classes
 *
 */

using Gtk;
using Tuner.Controllers;
using Tuner.Models;
using Gee;
using Tuner.Services;

/*
 * @class Tuner.TitleBox
 *
 * @brief The TitleBox sits at the top of the Window and presents the Header and Search controls
 *
 * @extends Gtk.Box
 */
public class Tuner.Widgets.TitleBox : Gtk.Box
{
    /* Public */

    // Signals
    public signal void searching_for_sig (string text);
    public signal void search_has_focus_sig ();


    /*
        Private 
    */

	private SearchEntry _search_entry = new SearchEntry ();

	/*
		Primary display assets
	*/

	private Revealer _revealer = new Revealer();
	private HeaderBar _headerbar;
		

    /**
     * @brief Construct block for initializing the TitleBox components.
     *
     * This method sets up the HeaderBar and SearchEntry and wires them up
	 * so that the Search panel drops down on the search button press
     *
     * @param app Application context for connectivity and app-level events.
     * @param window Parent window that owns this header bar.
     * @param player Player controller used for playback state and volume.
     * @param provider Data provider used for provider statistics tooltip text.
     */
    public TitleBox(Application app, Window window, PlayerController player, DataProvider.API provider)
    {
        Object (
            orientation: Gtk.Orientation.VERTICAL,
            spacing: 0
        );


		// Search 

		_search_entry.placeholder_text = _("Station Search");
		_search_entry.get_style_context().add_class("search-entry");
		_search_entry.set_margin_start(0);
		_search_entry.set_margin_end(0);
		_search_entry.set_margin_top(0);
		_search_entry.set_margin_bottom(0);
		_search_entry.valign = Align.CENTER;
		_search_entry.hexpand = true;
		_search_entry.activate.connect (() => {
			// Hide and reset search after submitting.
			_search_entry.text = "";
			_revealer.set_reveal_child(false);
		});
		_search_entry.changed.connect (() => {
			searching_for_sig(_search_entry.text);
		});
		_search_entry.focus_in_event.connect ((e) => {
			search_has_focus_sig ();
			return true;
		});

		// Background panel fills the revealer to avoid transparent gaps.
		var search_panel = new Box(Orientation.HORIZONTAL, 0);
		search_panel.margin = 0;
		search_panel.hexpand = true;
		_revealer.hexpand = true;
		search_panel.vexpand = true;
		search_panel.valign = Align.FILL;
		search_panel.halign = Align.FILL;
		search_panel.get_style_context().add_class("search-revealer-bg");

		// Centered wrapper so the entry can be sized relative to the revealer width.
		var search_wrap = new Box(Orientation.HORIZONTAL, 0);
		search_wrap.hexpand = true;
		search_wrap.halign = Align.CENTER;
		search_wrap.valign = Align.CENTER;
		search_wrap.margin_top = 3;
		search_wrap.margin_bottom = 3;
		_search_entry.halign = Align.CENTER;
		_search_entry.hexpand = false;
		search_wrap.add(_search_entry);
		search_panel.add(search_wrap);

		// Header Bar

		_headerbar = new HeaderBar(app, window, player, provider);
		_headerbar.search_toggle_sig.connect(() => {
			// Reset on open to avoid showing stale search text.
			var should_show = !_revealer.reveal_child;
			if (should_show)
				_search_entry.text = "";
			_revealer.set_reveal_child(should_show);
			if (_revealer.reveal_child)
				_search_entry.grab_focus();
		});

		// Revealer config
		_revealer.set_transition_type(RevealerTransitionType.SLIDE_UP);
		_revealer.reveal_child = false;
		_revealer.get_style_context().add_class("search-revealer-bg");
		_revealer.size_allocate.connect((allocation) => {
			// Keep the search entry at 1/3 of the revealer width.
			int target_width = (int)(allocation.width / 3);
			if (target_width > 0)
				_search_entry.set_size_request(target_width, -1);
		});


		// Add assets

		_revealer.add(search_panel);
		pack_start (_headerbar, false, false, 0);
		pack_start (_revealer, false, false, 0);

	} // HeaderBox

	
    /* 
        Public 
    */

	public void stream_info(bool show)
	{
		_headerbar.stream_info(show);
	}

	public void stream_info_fast(bool fast)
	{
		_headerbar.stream_info_fast(fast);
	}

	public void stream_info_dynamic_shrink(bool enabled)
	{
		_headerbar.stream_info_dynamic_shrink(enabled);
	}

	public bool update_playing_station(Station station)
	{
		return _headerbar.update_playing_station(station);
	}

	public Gee.List<string> get_hearted_titles()
	{
		return _headerbar.get_hearted_titles();
	}

	public Gee.List<string> get_hearted_history_lines_without_hearts()
	{
		return _headerbar.get_hearted_history_lines_without_hearts();
	}


} // Tuner.Widgets.TitleBox
