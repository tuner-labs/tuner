/**
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file PlayButton.vala
 * @author technosf
 * @date 2024-12-01
 * @since 2.0.0
 * @brief Player 'PLAY' button
 */

using Gtk;
using Tuner.Controllers;
using Tuner.Models;

/**
 * @class PlayButton
 *
 * @brief A custom widget that shows player state.
 *
 * PlayButton can control the player and does so by an ActionEvent linkage defined in the HeaderBar
 *
 * @extends Gtk.Button
 */
public class Tuner.Widgets.PlayButton : Gtk.Button
{

/* Constants    */

	private Image PLAY = new Gtk.Image.from_icon_name (
		"media-playback-start-symbolic",
		IconSize.LARGE_TOOLBAR
		);

	private Image BUFFERING = new Gtk.Image.from_icon_name (
		"media-playback-pause-symbolic",
		IconSize.LARGE_TOOLBAR
		);

	private Image STOP = new Gtk.Image.from_icon_name (
		"media-playback-stop-symbolic",
		IconSize.LARGE_TOOLBAR
		);

	private Image ERROR = new Gtk.Image.from_icon_name (
		"dialog-error-symbolic",
		IconSize.LARGE_TOOLBAR
		);

/* Public */

	/**
	* @class PlayButton
	*
	* @brief Create the play button and hook it up to the PlayerController
	*
	*/
	public PlayButton()
	{
		Object();

		image     = PLAY;
		sensitive = true;

		app().events.player_state_changed_sig.connect ((station, state) =>
		// Link the button image to the inverse of the player state
		{
			set_inverse_symbol (state);
		});
	} // construct


	/**
	* @brief Set the play button symbol and sensitivity
	*
	* This method is instigated from a player state change signal.
	* The app-level event bus invokes handlers on the main loop, so
	* UI updates are safe to apply synchronously here.
	*
	* @param state The new play state enum.
	*/
	private void set_inverse_symbol (StreamPlayer.State state)
	{

		tooltip_text  = null;
		switch (state)
		{
		case StreamPlayer.State.PLAYING:
			image         = STOP;
			image.opacity = 1.0;
			break;

		case StreamPlayer.State.BUFFERING:
			image         = BUFFERING;
			image.opacity = 0.5;
			break;

		case StreamPlayer.State.STOPPED_ERROR:
			image         = ERROR;
			image.opacity = 0.5;
			string? error_message = app().player.play_error_message;	// TODO Use signals?
			if (error_message == null || error_message.strip () == "")
				error_message = "An error occurred during playback.";
			tooltip_text = error_message;
			break;

		default:            //  STOPPED:
			image         = PLAY;
			image.opacity = 1.0;
			break;
		} // switch
	} // set_reverse_symbol
} // PlayButton
