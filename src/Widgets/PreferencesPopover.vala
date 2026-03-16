/**
 * SPDX-FileCopyrightText: Copyright © 2020-2024 Louis Brauer <louis@brauer.family>
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file PreferencesPopover.vala
 */

using Tuner.Models;

/**
 *
 * @brief Tuner preferences and selections.
 */
public class Tuner.Widgets.PreferencesPopover : Gtk.Popover
{

	construct // Construct the preferences popover widget
	{
		const int ROW_INDENT = 8;

		var about_menuitem = new Gtk.ModelButton ();
		about_menuitem.text        = _("About");
		about_menuitem.action_name = Window.ACTION_PREFIX + Window.ACTION_ABOUT;
		about_menuitem.margin_start = ROW_INDENT;

		// Voting
		var disable_tracking_item = new Gtk.ModelButton ();
		disable_tracking_item.text         = _("Do not participate in Station voting");
		disable_tracking_item.action_name  = Window.ACTION_PREFIX + Window.ACTION_DISABLE_TRACKING;
		disable_tracking_item.tooltip_text = _("If checked, your starred and streamed stations will not be used to calculate the Station index popularity vote, nor the popular and trending stations");
		disable_tracking_item.margin_start = ROW_INDENT;


		//Theme
		var theme_selector = new Base.SelectorButton (app().lookup_action ("set-theme-name"))
			.with_item (THEME.SYSTEM.get_name (), _("System"))
			.with_item (THEME.LIGHT.get_name (), _("Light mode"))
			.with_item (THEME.DARK.get_name (), _("Dark mode"))
			.with_active_id (app().settings.theme_mode);   

		var theme_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 3);
		theme_box.hexpand = true;
		theme_box.halign  = Gtk.Align.FILL;
		theme_box.pack_end (theme_selector, true, true, 5);
		theme_box.pack_end (new Gtk.Label(_("Theme")), false, false, 12);


		// Autoplay
		var autoplay_item = new Gtk.ModelButton ();
		autoplay_item.text         = _("Auto-play last station on startup");
		autoplay_item.action_name  = Window.ACTION_PREFIX + Window.ACTION_ENABLE_AUTOPLAY;
		autoplay_item.tooltip_text = _("If enabled, when Tuner starts it will automatically start to play the last played station");
		autoplay_item.margin_start = ROW_INDENT;


		// Restart Playing after network interruption
		var play_restart_item = new Gtk.ModelButton ();
		play_restart_item.text         = _("Restart playing after a network outage");
		play_restart_item.action_name  = Window.ACTION_PREFIX + Window.ACTION_ENABLE_PLAY_RESTART;
		play_restart_item.tooltip_text = _("If enabled, Tuner will restart playing the current station if it was stopped by a network outage");
		play_restart_item.margin_start = ROW_INDENT;


		// Start on Starred
		var start_on_starred = new Gtk.ModelButton ();
		start_on_starred.text         = _("Open to Starred Stations");
		start_on_starred.action_name  = Window.ACTION_PREFIX + Window.ACTION_START_ON_STARRED;
		start_on_starred.tooltip_text = _("If enabled, when Tuner starts it will open to the starred stations view");
		start_on_starred.margin_start = ROW_INDENT;


		// Play Display
		var stream_info = new Gtk.ModelButton ();
		stream_info.text         = _("Show stream info when playing");
		stream_info.action_name  = Window.ACTION_PREFIX + Window.ACTION_STREAM_INFO;
		stream_info.tooltip_text = _("Cycle through the metadata from the playing stream");
		stream_info.margin_start = ROW_INDENT;

		var stream_info_fast = new Gtk.ModelButton ();
		stream_info_fast.text         = _("Faster cycling through stream info");
		stream_info_fast.action_name  = Window.ACTION_PREFIX + Window.ACTION_STREAM_INFO_FAST;
		stream_info_fast.tooltip_text = _("Fast cycle through the metadata from the playing stream if show stream info is enabled");
		stream_info_fast.margin_start = ROW_INDENT;

		var stream_info_image_popup = new Gtk.ModelButton ();
		stream_info_image_popup.text         = _("Stream metadata image popup");
		stream_info_image_popup.action_name  = Window.ACTION_PREFIX + Window.ACTION_STREAM_INFO_IMAGE_POPUP;
		stream_info_image_popup.tooltip_text = _("Show a movable popup with images discovered in the stream metadata");
		stream_info_image_popup.margin_start = ROW_INDENT;


/* 
	Enable in-app language selection for local debug or if specifically set in build options
*/
#if DEBUG_LOCAL 

		var lang_selector = new Base.SelectorButton (app().lookup_action ("set-language"))
			.with_item("", "Default")
			.with_items (Languages.get_language_map())
			.with_active_id(app().settings.language);

		var lang_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
		lang_box.hexpand = true;
		lang_box.halign  = Gtk.Align.FILL;
		lang_box.pack_end (lang_selector, true, true, 5);
		lang_box.pack_end (new Gtk.Label(_("Language")), false, false, 12);
		lang_box.tooltip_text = _("Language changes restart Tuner");
		
#endif
// end language selection


		// Export starred
		var export_starred = new Gtk.ModelButton ();
		export_starred.text = _("Export Starred Stations to Playlist");
		export_starred.margin_start = ROW_INDENT;
		export_starred.button_press_event.connect (() =>
		{
			export_m3u8 ();
		});


		// Import starred
		var import_starred = new Gtk.ModelButton ();
		import_starred.text = _("Import Station UUIDs as Starred Stations");
		import_starred.margin_start = ROW_INDENT;
		import_starred.button_press_event.connect (() =>
		{
			import_stationuuids ();
		});


		// Layout
		uint8 vpos      = 0;
		var   menu_grid = new Gtk.Grid ();
		menu_grid.margin_bottom = 10;
		menu_grid.margin_top    = 10;
		menu_grid.margin_start  = 5;
		menu_grid.margin_end    = 5;
		menu_grid.row_spacing   = 3;
		menu_grid.orientation   = Gtk.Orientation.VERTICAL;

		menu_grid.attach (theme_box, 0, vpos++, 4, 1);

		menu_grid.attach (new Gtk.SeparatorMenuItem (), 0, vpos++, 4, 1);

		menu_grid.attach (start_on_starred, 0, vpos++, 4, 1);

		menu_grid.attach (new Gtk.SeparatorMenuItem (), 0, vpos++, 4, 1);

		menu_grid.attach (autoplay_item, 0, vpos++, 4, 1);

		menu_grid.attach (play_restart_item, 0, vpos++, 4, 1);

		menu_grid.attach (new Gtk.SeparatorMenuItem (), 0, vpos++, 4, 1);
		
		menu_grid.attach (stream_info, 0, vpos++, 4, 1);
		menu_grid.attach (stream_info_fast, 0, vpos++, 4, 1);
		menu_grid.attach (stream_info_image_popup, 0, vpos++, 4, 1);

		menu_grid.attach (new Gtk.SeparatorMenuItem (), 0, vpos++, 4, 1);

		menu_grid.attach (export_starred, 0, vpos++, 4, 1);

		menu_grid.attach (new Gtk.SeparatorMenuItem (), 0, vpos++, 4, 1);

		menu_grid.attach (import_starred, 0, vpos++, 4, 1);

		menu_grid.attach (new Gtk.SeparatorMenuItem (), 0, vpos++, 4, 1);

		menu_grid.attach (disable_tracking_item, 0, vpos++, 4, 1);

		menu_grid.attach (new Gtk.SeparatorMenuItem (), 0, vpos++, 4, 1);

		/* 
			Enable in-app language selection for local debug or if specifically set in build options
		*/
		#if DEBUG_LOCAL || ENABLE_IN_APP_LANGUAGE_SELECTION

		menu_grid.attach (lang_box, 0, vpos++, 4, 1);

		menu_grid.attach (new Gtk.SeparatorMenuItem (), 0, vpos++, 4, 1);

		#endif
		// end language selection

		menu_grid.attach (about_menuitem, 0, vpos++, 4, 1);
		
		menu_grid.show_all ();

		this.add (menu_grid);
	}     // construct


	/**
	* @brief Export Starred Stations as a m3u playlist
	*
	*
	*/
	public void export_m3u8()
	{
		try
		{
			string temp_file;
			GLib.FileUtils.open_tmp ("XXXXXX.starred.m3u8", out temp_file);
			GLib.FileUtils.set_contents(temp_file, app().stars.export_m3u8 ());

			// Create the file chooser dialog for saving the exported playlist					
			var dialog = new Gtk.FileChooserDialog(
			_("Save File"),
			app().window,
			Gtk.FileChooserAction.SAVE,
			_("_Cancel"), Gtk.ResponseType.CANCEL,
			_("_Save"), Gtk.ResponseType.ACCEPT
			);
			
			// Suggest a default filename
			dialog.set_current_name("tuner-starred."+(new DateTime.now_local().format("%Y-%m-%d"))+".m3u8");

			if (dialog.run() == Gtk.ResponseType.ACCEPT)
			{
				string save_path = dialog.get_filename();
				// Copy the temp file to the chosen location
				var source_file = GLib.File.new_for_path(temp_file);
				var dest_file   = GLib.File.new_for_path(save_path);
				source_file.copy(dest_file, GLib.FileCopyFlags.OVERWRITE); // Overwrite
			} // if

			dialog.destroy();

		} // try
		catch (GLib.Error e)
		{
			//warning("Error: $(e.message)");
			warning ((_("Error") + ": %s").printf (e.message));
		} // catch
	}     // export_m3u8


	/**
	* @brief Select and read a file for Station UUIDs to be imported as Starred
	*
	*
	*/
	public void import_stationuuids()
	{
		var dialog = new Gtk.FileChooserDialog(
			_("Choose a file"),
			app().window,
			Gtk.FileChooserAction.OPEN,
			_("_Cancel"), Gtk.ResponseType.CANCEL,
			_("_Open"), Gtk.ResponseType.ACCEPT
			);

		string filepath;

		if (dialog.run() == Gtk.ResponseType.ACCEPT)
		{
			filepath = dialog.get_filename();

			try
			{
				var file   = File.new_for_path(filepath);
				FileInputStream stream = file.read();

				// Read content into a string buffer
				DataInputStream data_stream = new DataInputStream(stream);

				app().stars.import_stationuuids (data_stream);

				stream.close();
			} catch (Error e)
			{
				//warning("Error reading file: $(e.message)");
				warning ((_("Error reading file") + ": %s").printf (e.message));
			}
		} // if

		dialog.destroy();

	} // import_stationuuids

} // class PreferencesPopover
