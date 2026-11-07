/**
 * SPDX-FileCopyrightText: Copyright © 2020-2024 Louis Brauer <louis@brauer.family>
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file Backdrop.vala
 *
 * @brief The faint animated picture behind the display's pages.
 */

using Tuner.Models;
using Tuner.Widgets.Base;

/**
 * @brief The animated tuner or jukebox icon that sits, faint, behind the station pages.
 *
 * The tuner icon shows normally and the jukebox icon in shuffle mode, crossfading between them.
 * Both turn to a position taken from the station playing, so the dial moves when the station changes.
 */
public class Tuner.Widgets.Backdrop : Gtk.Fixed
{
	private const double OPACITY            = 0.15;
	private const int TRANSITION_TIME_MS    = 1500;
	private const Gtk.RevealerTransitionType TRANSITION_TYPE = Gtk.RevealerTransitionType.CROSSFADE;

	private Gtk.Revealer _tuner_revealer   = new Gtk.Revealer ();
	private Gtk.Revealer _jukebox_revealer = new Gtk.Revealer ();
	private AnimatedTunerIcon _tuner_icon   = new AnimatedTunerIcon (256, 256);
	private AnimatedJukeboxIcon _jukebox_icon = new AnimatedJukeboxIcon (256, 256);


	public Backdrop ()
	{
		Object ();

		fit (_tuner_revealer, _tuner_icon, true);
		fit (_jukebox_revealer, _jukebox_icon, false);

		add (_tuner_revealer);
		add (_jukebox_revealer);
		halign = Gtk.Align.CENTER;
		valign = Gtk.Align.CENTER;
	} // Backdrop


	/**
	 * @brief Shows the jukebox icon (shuffle mode) or the tuner icon.
	 */
	public void show_jukebox (bool jukebox)
	{
		_tuner_revealer.reveal_child   = !jukebox;
		_jukebox_revealer.reveal_child = jukebox;
	} // show_jukebox


	/**
	 * @brief Turns both icons to a position taken from the station, so each station has its own.
	 */
	public void tune_to (Station station)
	{
		string key  = station.stationuuid != "" ? station.stationuuid : station.name;
		double norm = (double) (GLib.str_hash (key) % 1000) / 999.0;
		_tuner_icon.animate_to (norm);
		_jukebox_icon.animate_to (norm);
	} // tune_to


	private void fit (Gtk.Revealer revealer, Gtk.Widget icon, bool revealed)
	{
		icon.opacity                = OPACITY;
		revealer.transition_duration = TRANSITION_TIME_MS;
		revealer.transition_type     = TRANSITION_TYPE;
		revealer.reveal_child        = revealed;
		revealer.child               = icon;
	} // fit
} // Backdrop
