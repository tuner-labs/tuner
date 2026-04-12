/**
 * SPDX-FileCopyrightText: Copyright © 2026technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file TunerStatus.vala
 *
 * @brief TunerStatus widget
 *
 */


using Gtk;
using Rsvg;
using Tuner.Controllers;
using Tuner.Models;
using Tuner.Services;

/**
 * @brief Animated tuner icon that slides the needle and rotates the knob indicator.
 *
 * Renders the tuner SVG from resources, then animates sub-layers:
 * - `tuner-base`: static art
 * - `needle-position`: translated horizontally across the dial
 * - `knob-rotation`: rotated around the knob center
 */
public class Tuner.Widgets.Base.AnimatedTunerIcon : Gtk.DrawingArea
{
	// SVG coordinate system is 128x128. These match the artwork geometry.
	private const double DIAL_OVERSHOOT = 5.0;
	private const double DIAL_LEFT_X = 23.0;
	private const double DIAL_RIGHT_X = 105.0;
	private const double NEEDLE_BASE_X = 54.0; // original needle x in SVG
	private const double NEEDLE_MIN_X = DIAL_LEFT_X - DIAL_OVERSHOOT;
	private const double NEEDLE_MAX_X = DIAL_RIGHT_X + DIAL_OVERSHOOT;
	// Layer_2 is translated by (0, -8) in the SVG, so the root-space center
	// is original center + LAYER_OFFSET_Y.
	private const double LAYER_OFFSET_Y = -8.0;
	private const double KNOB_CENTER_X = 64.5;
	private const double KNOB_CENTER_Y = 98.5 + LAYER_OFFSET_Y;
	private const double KNOB_TURNS = 3.0; // full needle sweep = 3 full knob rotations
	private const int ANIMATION_DURATION_MS = 2000; // full sweep duration

	private Rsvg.Handle _handle;
	private uint _animation_tick_id = 0;
	private int64 _animation_start_us = 0;
	private double _needle_offset = 0.0;
	private double _knob_angle = 0.0;
	private double _start_needle_offset = 0.0;
	private double _start_knob_angle = 0.0;
	private double _target_needle_offset = 0.0;
	private double _target_knob_angle = 0.0;
	private double _target_norm = 0.5;
	private bool _return_on_complete = false;
	private double _return_norm = 0.5;

	/**
	 * @brief Create an animated tuner icon with an optional fixed size.
	 * @param width Optional pixel width (defaults to IconSize.DIALOG).
	 * @param height Optional pixel height (defaults to IconSize.DIALOG).
	 */
	public AnimatedTunerIcon (int? width = null, int? height = null)
	{
		set_halign (Align.CENTER);
		set_valign (Align.CENTER);

		int icon_width = 64;
		int icon_height = 64;
		IconSize.lookup (IconSize.DIALOG, out icon_width, out icon_height);
		set_size_request (width ?? icon_width, height ?? icon_height);

		// Load the SVG icon from GResource so we can render individual elements.
		try {
			var bytes = GLib.resources_lookup_data ("/io/github/tuner_labs/tuner/icons/tuner:tuner-on.svg", GLib.ResourceLookupFlags.NONE);
			_handle = new Rsvg.Handle.from_data (bytes.get_data ());
		} catch (GLib.Error e) {
			warning ("Failed to load tuner SVG for animation: %s", e.message);
		}

		// Drive drawing via the widget's draw signal.
		// Initialize to the SVG's original needle position.
		_needle_offset = 0.0;
		_knob_angle = 0.0;

		draw.connect (on_draw);
		destroy.connect (() =>
		{
			if (_animation_tick_id != 0) {
				remove_tick_callback (_animation_tick_id);
				_animation_tick_id = 0;
			}
		});
	}

	/**
	 * @brief Animate the tuner to a normalized dial position.
	 * @param normalized_position 0.0 = dial-left, 1.0 = dial-right.
	 */
	public void animate_to (double normalized_position)
	{
		start_animation (normalized_position, false, 0.5);
	}

	/**
	 * @brief Animate out-and-back around a center position.
	 * @param center_norm Center position to return to.
	 * @param delta_norm Offset to move away before returning.
	 */
	public void animate_pulse (double center_norm, double delta_norm)
	{
		double target = center_norm + delta_norm;
		start_animation (target, true, center_norm);
	}

	/**
	 * @brief Internal animation setup shared by animate_to and animate_pulse.
	 */
	private void start_animation (double normalized_position, bool return_on_complete, double return_norm)
	{
		// Clamp the target and store optional return target.
		_target_norm = Math.fmax (0.0, Math.fmin (1.0, normalized_position));
		_return_on_complete = return_on_complete;
		_return_norm = Math.fmax (0.0, Math.fmin (1.0, return_norm));

		// Map normalized value to needle offset and knob rotation.
		_target_needle_offset = (NEEDLE_MIN_X + _target_norm * (NEEDLE_MAX_X - NEEDLE_MIN_X)) - NEEDLE_BASE_X;
		_target_knob_angle = (_target_norm - 0.5) * 360.0 * KNOB_TURNS;

		// Capture the current state as the animation start.
		_start_needle_offset = _needle_offset;
		_start_knob_angle = _knob_angle;
		_animation_start_us = 0;

		// Use frame clock ticks to keep motion smooth and synced to refresh.
		if (_animation_tick_id == 0)
			_animation_tick_id = add_tick_callback (on_animation_tick);
	}

	/**
	 * @brief Frame-clock tick callback. Updates interpolation and triggers redraw.
	 * @return false when the animation completes (stops tick), true to continue.
	 */
	private bool on_animation_tick (Gtk.Widget widget, Gdk.FrameClock frame_clock)
	{
		int64 frame_us = frame_clock.get_frame_time ();
		if (_animation_start_us == 0)
			_animation_start_us = frame_us;

		double elapsed_ms = (frame_us - _animation_start_us) / 1000.0;
		double progress = elapsed_ms / ANIMATION_DURATION_MS;

		if (progress >= 1.0) {
			_needle_offset = _target_needle_offset;
			_knob_angle = _target_knob_angle;
			queue_draw ();

			if (_return_on_complete) {
				// Start the return leg without stopping the tick.
				_return_on_complete = false;
				start_animation (_return_norm, false, _return_norm);
				return true;
			}

			_animation_tick_id = 0;
			_animation_start_us = 0;
			return false;
		}

		// Ease-out for a smoother glide instead of a linear jump.
		double eased = 1.0 - Math.pow (1.0 - progress, 3.0);
		_needle_offset = _start_needle_offset + ((_target_needle_offset - _start_needle_offset) * eased);
		_knob_angle = _start_knob_angle + ((_target_knob_angle - _start_knob_angle) * eased);
		queue_draw ();
		return true;
	}
	/**
	 * @brief Draw handler. Renders SVG layers with animation transforms.
	 */
	private bool on_draw (Cairo.Context cr)
	{
		if (_handle == null) {
			return false;
		}

		int width = get_allocated_width ();
		int height = get_allocated_height ();
		var dims = _handle.get_dimensions ();

		if (dims.width == 0 || dims.height == 0 || width == 0 || height == 0) {
			return false;
		}

		// Keep uniform scaling so rotations don't skew when the widget isn't square.
		double scale = Math.fmin ((double) width / (double) dims.width,
			(double) height / (double) dims.height);
		double tx = ((double) width - ((double) dims.width * scale)) / 2.0;
		double ty = ((double) height - ((double) dims.height * scale)) / 2.0;

		cr.save ();
		cr.translate (tx, ty);
		cr.scale (scale, scale);

		// Draw base first, then move the needle horizontally, then rotate knob indicator.
		render_static (cr, "tuner-base");
		render_translated (cr, "needle-position", _needle_offset, 0.0);
		render_rotated (cr, "knob-rotation", _knob_angle);

		cr.restore ();
		return false;
	}

	/**
	 * @brief Render an SVG element by id without transforms.
	 */
	private void render_static (Cairo.Context cr, string id)
	{
		_handle.render_cairo_sub (cr, "#" + id);
	}

	/**
	 * @brief Render an SVG element by id with a translation.
	 * @param dx X translation in SVG units.
	 * @param dy Y translation in SVG units.
	 */
	private void render_translated (Cairo.Context cr, string id, double dx, double dy)
	{
		cr.save ();
		cr.translate (dx, dy);
		_handle.render_cairo_sub (cr, "#" + id);
		cr.restore ();
	}

	/**
	 * @brief Render an SVG element by id with rotation around the knob center.
	 * @param angle_deg Rotation angle in degrees.
	 */
	private void render_rotated (Cairo.Context cr, string id, double angle_deg)
	{
		cr.save ();
		// 1) Move the origin to the knob center so rotation pivots around it.
		cr.translate (KNOB_CENTER_X, KNOB_CENTER_Y);
		// 2) Rotate the coordinate system by the desired angle (degrees -> radians).
		cr.rotate (angle_deg * Math.PI / 180.0);
		// 3) Move the origin back so SVG element coordinates remain in their original space.
		cr.translate (-KNOB_CENTER_X, -KNOB_CENTER_Y);

		// The indicator path is authored in absolute SVG coordinates. After the
		// translate/rotate/translate, any point (x, y) is rotated around
		// (KNOB_CENTER_X, KNOB_CENTER_Y), so its locus is a circle centered there.
		_handle.render_cairo_sub (cr, "#" + id);

		cr.restore ();
	}
}

/** 
 * TunerStatus widget for displaying tuner on-line status and data provider information.
 */
public class Tuner.Widgets.Base.TunerStatus : Fixed
{
	private Overlay _tuner_icon = new Overlay();
	private AnimatedTunerIcon _tuner_on = new AnimatedTunerIcon();
	private double _last_norm = 0.5;
	private const double ONLINE_PULSE_DELTA = 0.12;

    public TunerStatus(Application app, Window window, DataProvider.API provider) 
    {
            // Tuner icon
        _tuner_icon.add(new Image.from_icon_name("tuner:tuner-off", IconSize.DIALOG));
        _tuner_icon.add_overlay(_tuner_on);
        _tuner_icon.valign = Align.START;

		add(_tuner_icon);
		set_valign(Align.CENTER);
		set_margin_bottom(5);   // 20px padding on the right
		set_margin_start(5);   // 20px padding on the right
		set_margin_end(5);   // 20px padding on the right
		tooltip_text = _("Data Provider");
		query_tooltip.connect((x, y, keyboard_tooltip, tooltip) =>
		{
			
				if (app.is_offline)
					return false;
				string provider_text = _("Data Provider") + ": %s\n\n%u " + _("Stations") + ",\t%u " + _("Tags");
				tooltip.set_text (provider_text.printf (window.directory.provider (),
				provider.available_stations (),
				provider.available_tags ()
				));

			return true;
		});

		// Animate the needle/knob on station changes using a stable per-station hash.
		app.events.station_changed_sig.connect((station) =>
		{
			if (app.is_offline)
				return;

			// Deterministic placement per station so the needle lands consistently.
			string key = station.stationuuid != "" ? station.stationuuid : station.name;
			uint hash = GLib.str_hash (key);
			_last_norm = (double) (hash % 1000) / 999.0;
			_tuner_on.animate_to (_last_norm);
		});
    } // construct


    /**
     * Sets the online status of the tuner.
     * @param show_online Whether the tuner is online.
     */
    public bool online 
    {
        set {
            _tuner_on.opacity = value ? 1.0 : 0.0;
			if (value) {
				// Online pulse: move away then return to the current station position.
				_tuner_on.animate_pulse (_last_norm, ONLINE_PULSE_DELTA);
			}
        }
    } // online


} // TunerStatus
