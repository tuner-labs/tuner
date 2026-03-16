/**
 * SPDX-FileCopyrightText: Copyright © 2020-2024 Louis Brauer <louis@brauer.family>
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file StationList.vala
 */

using Gee;
using Tuner.Models;

/**
 * @class StationList
 * @brief A widget for displaying and managing a list of radio stations.
 *
 * The StationList class extends ListFlowBox to provide a specialized
 * widget for displaying radio stations. It manages station selection.
 *
 * @extends ListFlowBox
 */
public class Tuner.Widgets.Base.StationList : ListFlowBox
{
	/**
	* @brief Emitted after the user reorders stations via drag-and-drop.
	*
	* @param stationuuids The reordered list of station UUIDs.
	*/
	public signal void reordered (Gee.List<string> stationuuids);

	private bool _reorderable = false;
	private bool _reorder_dnd_enabled = false;
	/**
	* @signal selection_changed
	*
	* @brief Emitted when a station is selected.
	*
	* @param station The selected Model.Station.
	*/
	public signal void station_clicked_sig (Station station);


	/**
	* @brief Constructs a new StationList instance.
	*
	* Initializes the StationList with default properties for layout and behavior.
	*/
	public StationList ()
	{
		Object (
			homogeneous: false,
			min_children_per_line: 1,
			max_children_per_line: 3,
			column_spacing: 5,
			row_spacing: 5,
			border_width: 20,
			valign: Gtk.Align.START,
			selection_mode: Gtk.SelectionMode.NONE
			);
		get_style_context().add_class ("station-list");
	} // StationList


	/**
	* @brief Constructs a new StationList instance with a predefined list of stations.
	*
	* Takes the stations, wraps them as buttons and adds them to the flowbox.
	*
	* @param stations The ArrayList of Model.Station objects to populate the list.
	*/
	public static StationList? with_stations (Gee.Collection<Station>? stations)
	{
		if (stations == null)
			return null;
		StationList list = new StationList ();
		list.stations = stations;
		return list;
	} // StationList.with_stations


	/**
	* @brief The list of stations to display.
	*
	* When set, this property clears the existing list and populates it with
	* the new stations. It also sets up signal connections for each station.
	*/
	public Collection<Station> stations 
	{
		// FIXME Wraps stations in StationButtons, adds to flowbox
		set construct {
			clear ();
			if (value == null)
				return;

			foreach (var station in value)
			{
			var box = new StationButton (station);
			box.clicked.connect (() => {
				station_clicked_sig (box.station);
			});
			if (_reorderable)
				configure_button_for_reorder (box);
			add (box);
			var flow_child = box.get_parent () as Gtk.FlowBoxChild;
			if (flow_child != null)
				flow_child.can_focus = false;
			}
			item_count = value.size;
			if (_reorderable)
				enable_reorder_dnd ();
		}
	} // stations


	/**
	* @brief Enables drag-and-drop reordering for this list.
	*
	* Only intended for starred stations.
	*/
	public bool reorderable {
		get { return _reorderable; }
		set {
			_reorderable = value;
			if (_reorderable)
				enable_reorder_dnd ();
		}
	}


	/**
	* @brief Clears all stations from the list.
	*
	* This method removes and destroys all child widgets from the StationList.
	*/
	public void clear ()
	{
		var children = get_children();
		foreach (var c in children)
		{
			c.destroy();
		}
	} // clear

	// -------------------------------
	// Drag-and-drop reordering
	// -------------------------------

	private void enable_reorder_dnd ()
	{
		if (_reorder_dnd_enabled)
			return;
		_reorder_dnd_enabled = true;

		// GTK3: use flowbox as drop target and transfer via text/plain.
		var targets = setup_drag_targets ();

		// Accept drops at the flowbox level so GTK can find a target.
		Gtk.drag_dest_set (this, Gtk.DestDefaults.ALL, targets, Gdk.DragAction.MOVE);
		drag_motion.connect ((context, x, y, time) => {
			Gdk.drag_status (context, Gdk.DragAction.MOVE, time);
			return true;
		});
		drag_drop.connect ((context, x, y, time) => {
			// Request plain text; selection.set_text uses the text/plain target in GTK3.
			Gtk.drag_get_data (this, context, Gdk.Atom.intern ("text/plain", false), time);
			return true;
		});
		drag_data_received.connect ((context, x, y, selection, info, time) => {
			var source_uuid = selection.get_text ();
			if (source_uuid == null) {
				Gtk.drag_finish (context, false, false, time);
				return;
			}

			var dest_child = get_child_at_pos (x, y);
			if (dest_child == null) {
				reorder_to_end (source_uuid);
				Gtk.drag_finish (context, true, true, time);
				return;
			}

			var dest_station = station_for_child (dest_child);
			if (dest_station == null) {
				reorder_to_end (source_uuid);
				Gtk.drag_finish (context, true, true, time);
				return;
			}

			if (source_uuid == dest_station.stationuuid) {
				Gtk.drag_finish (context, false, false, time);
				return;
			}

			reorder_by_uuid (source_uuid, dest_station.stationuuid);
			Gtk.drag_finish (context, true, true, time);
		});

		drag_end.connect ((context) => {
			emit_reordered ();
		});

		foreach (var child in get_children())
		{
			var flow_child = child as Gtk.FlowBoxChild;
			if (flow_child == null)
				continue;
			var widget = flow_child.get_child ();
			var button = widget as StationButton;
			if (button != null)
				configure_button_for_reorder (button);
		}
	}

	private void configure_button_for_reorder (StationButton button)
	{
		var targets = setup_drag_targets ();

		button.get_style_context().add_class("reorderable");
		Gtk.drag_source_set (button, Gdk.ModifierType.BUTTON1_MASK, targets, Gdk.DragAction.MOVE);
		button.drag_begin.connect ((context) => {
			set_drag_icon (button, context);
		});
		button.drag_failed.connect ((context, result) => { return false; });
		button.drag_data_get.connect ((context, selection, info, time) => {
			var station = button.station;
			if (station == null)
				return;
			selection.set_text (station.stationuuid, -1);
		});
	}

	private Station? station_for_child (Gtk.FlowBoxChild flow_child)
	{
		var widget = flow_child.get_child ();
		var button = widget as StationButton;
		return button != null ? button.station : null;
	}

	private Gtk.FlowBoxChild? flow_child_for_uuid (string uuid)
	{
		foreach (var child in get_children ())
		{
			var flow_child = child as Gtk.FlowBoxChild;
			if (flow_child == null)
				continue;
			var station = station_for_child (flow_child);
			if (station != null && station.stationuuid == uuid)
				return flow_child;
		}
		return null;
	}

	private void reorder_by_uuid (string source_uuid, string dest_uuid)
	{
		var source_child = flow_child_for_uuid (source_uuid);
		var dest_child = flow_child_for_uuid (dest_uuid);
		if (source_child == null || dest_child == null)
		{
			return;
		}

		int source_index = -1;
		int dest_index = -1;
		int index = 0;
		foreach (var child in get_children ())
		{
			var flow_child = child as Gtk.FlowBoxChild;
			if (flow_child == null) {
				index++;
				continue;
			}
			if (flow_child == source_child)
				source_index = index;
			if (flow_child == dest_child)
				dest_index = index;
			index++;
		}
		if (source_index < 0 || dest_index < 0)
		{
			return;
		}

		// Removing a widget can destroy it; hold a ref while reordering.
		source_child.ref ();
		remove (source_child);
		if (source_index < dest_index)
			dest_index -= 1;
		insert (source_child, dest_index);
		source_child.unref ();
		show_all ();
		emit_reordered ();
	}

	private void reorder_to_end (string source_uuid)
	{
		var source_child = flow_child_for_uuid (source_uuid);
		if (source_child == null) {
			return;
		}

		int count = 0;
		foreach (var child in get_children ())
		{
			if (child is Gtk.FlowBoxChild)
				count++;
		}

		source_child.ref ();
		remove (source_child);
		insert (source_child, count - 1);
		source_child.unref ();
		show_all ();
		emit_reordered ();
	}

	private void emit_reordered ()
	{
		var ordered = new Gee.ArrayList<string>();
		foreach (var child in get_children ())
		{
			var flow_child = child as Gtk.FlowBoxChild;
			if (flow_child == null)
				continue;
			var station = station_for_child (flow_child);
			if (station != null)
				ordered.add (station.stationuuid);
		}
		reordered (ordered);
	}

	// GTK3 DnD target list shared by sources and destinations.
	private Gtk.TargetEntry[] setup_drag_targets ()
	{
		return new Gtk.TargetEntry[] {
			{ "text/plain", Gtk.TargetFlags.SAME_APP, 1 }
		};
	}

	// Render the station button as the drag ghost.
	private void set_drag_icon (StationButton button, Gdk.DragContext context)
	{
		var toplevel = button.get_toplevel () as Gtk.Widget;
		if (toplevel == null)
			return;

		var window = toplevel.get_window ();
		if (window == null) {
			Gtk.drag_set_icon_name (context, "view-list-symbolic", 0, 0);
			return;
		}

		int tx = 0;
		int ty = 0;
		button.translate_coordinates (toplevel, 0, 0, out tx, out ty);

		Gtk.Allocation alloc;
		button.get_allocation (out alloc);
		var pixbuf = Gdk.pixbuf_get_from_window (window, tx, ty, alloc.width, alloc.height);
		if (pixbuf != null)
		{
			// Scale the ghost to avoid oversized drag feedback.
			int target_w = (int)(alloc.width * 0.75);
			int target_h = (int)(alloc.height * 0.75);
			if (target_w < 24) target_w = 24;
			if (target_h < 24) target_h = 24;
			var scaled = pixbuf.scale_simple (target_w, target_h, Gdk.InterpType.BILINEAR);
			if (scaled != null)
				Gtk.drag_set_icon_pixbuf (context, scaled, target_w / 2, target_h / 2);
			else
				Gtk.drag_set_icon_pixbuf (context, pixbuf, alloc.width / 2, alloc.height / 2);
			return;
		}

		Gtk.drag_set_icon_name (context, "view-list-symbolic", 0, 0);
	}
} // StationList
