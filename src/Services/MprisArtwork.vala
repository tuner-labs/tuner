/**
 * SPDX-FileCopyrightText: Copyright © 2020-2024 Louis Brauer <louis@brauer.family>
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file MprisArtwork.vala
 *
 * @brief Chooses the artwork that MPRIS clients show for the station playing.
 */

using Tuner.Models;

namespace Tuner.Services.DBus {

	/**
	 * @brief Chooses the artwork address that MPRIS clients (the desktop's media controls) show.
	 *
	 * In order: the error icon while the station has stopped on an error, the image the stream provides,
	 * the station's favicon once it has loaded, and last the stock icon (Tuner, or jukebox in shuffle mode).
	 * MPRIS clients read artwork from an address, not from inside the app, so each stock icon is drawn to a
	 * PNG in the cache folder the first time it is needed.
	 */
	public class MprisArtwork : Object
	{
		private const string ICON_RESOURCE         = "/io/github/tuner_labs/tuner/icons/tuner:tuner-on.svg";
		private const string JUKEBOX_ICON_RESOURCE = "/io/github/tuner_labs/tuner/icons/tuner:jukebox.svg";
		private const string ERROR_ICON_RESOURCE   = "/io/github/tuner_labs/tuner/icons/tuner:error.svg";
		private const int ICON_SIZE_PX = 512;

		/** @brief True while the station has stopped on a playback error: the error icon shows */
		public bool in_error { get; set; default = false; }

		/** @brief True in jukebox (shuffle) mode: the stock icon is the jukebox icon */
		public bool shuffle { get; set; default = false; }

		/** @brief Emitted when the artwork changed by itself: a favicon finished loading */
		public signal void changed ();

		private string? _cache_dir;
		private Station? _station = null;                // The station playing
		private string? _chosen = null;                  // Artwork chosen for it: null or "" means the stock icon
		private string _stream_image = "";               // Image address from the stream's metadata, if any
		private Station? _favicon_watched = null;        // Station whose favicon load is being waited for
		private ulong _favicon_watch_id = 0;
		private string? _tuner_art_url = null;           // Tuner icon as a file address, made when first needed
		private string? _jukebox_art_url = null;         // Jukebox icon as a file address, made when first needed
		private string? _error_art_url = null;           // Error icon as a file address, made when first needed


		/**
		 * @param cache_dir Folder the stock icons are drawn to, or null if there is none
		 */
		public MprisArtwork (string? cache_dir)
		{
			Object ();
			_cache_dir = cache_dir;
		} // MprisArtwork


		/**
		 * @brief A new station starts: forget the old station's artwork and take the new station's.
		 */
		public void station_changed (Station station)
		{
			_station      = station;
			in_error      = false;
			_stream_image = "";
			_chosen       = choose (station);
			watch_favicon (station);
		} // station_changed


		/**
		 * @brief The stream sent metadata: use its image if it has one.
		 *
		 * @param image_url The image address in the metadata, or "" if it has none
		 */
		public void metadata_changed (Station station, string image_url)
		{
			_station      = station;
			_stream_image = image_url;
			_chosen       = choose (station);
		} // metadata_changed


		/**
		 * @brief True when there is no artwork of its own and the stock icon is shown.
		 */
		public bool is_stock_icon ()
		{
			return _chosen == null || _chosen == "";
		} // is_stock_icon


		/**
		 * @brief The artwork to show now, as an address.
		 *
		 * If the stock icon could not be drawn the result is "file:///", which shows no image.
		 */
		public string url ()
		{
			if (in_error)
			{
				if (_error_art_url == null)
					_error_art_url = make_icon_file (ERROR_ICON_RESOURCE, "mpris-error-icon.png");
				return _error_art_url;
			}
			return is_stock_icon () ? stock_url () : _chosen;
		} // url


		/**
		 * @brief Picks the artwork for a station: null means use the stock icon.
		 *
		 * In order: the image the stream provides, then the station's favicon if it has actually
		 * loaded (a favicon address that is dead would leave a client showing the previous
		 * station's picture), then null.
		 */
		private string? choose (Station station)
		{
			string? art = null;
			if (_stream_image != "")
				art = _stream_image;
			else if (station.favicon != null && station.favicon != "" && station.favicon_loaded () > 0)
				art = station.favicon;

			string chosen = art != null ? art : "stock icon";
			if (Tuner.debug_enabled ())
				debug (@"[mpris] artwork for '$(station.name)': stream image='$_stream_image' favicon='$(station.favicon)' favicon loaded=$(station.favicon_loaded ()) -> $chosen");
			return art;
		} // choose


		/**
		 * @brief Waits for the station's favicon to finish loading, to use it once it has.
		 *
		 * The favicon downloads in the background, so it may not be ready the moment a station starts.
		 */
		private void watch_favicon (Station station)
		{
			if (_favicon_watched != null)
			{
				SignalHandler.disconnect (_favicon_watched, _favicon_watch_id);
				_favicon_watched  = null;
				_favicon_watch_id = 0;
			}

			if (station.favicon == null || station.favicon == "" || station.favicon_loaded () > 0)
				return;

			_favicon_watched  = station;
			_favicon_watch_id = station.favicon_sig.connect (() =>
			{
				if (_station != station)
					return;

				_chosen = choose (station);
				changed ();
			});
		} // watch_favicon


		/**
		 * @brief The icon to show for a station with no artwork of its own, as a file address.
		 *
		 * The jukebox icon while in jukebox (shuffle) mode, otherwise the Tuner icon.
		 */
		private string stock_url ()
		{
			if (shuffle)
			{
				if (_jukebox_art_url == null)
					_jukebox_art_url = make_icon_file (JUKEBOX_ICON_RESOURCE, "mpris-jukebox-icon.png");
				return _jukebox_art_url;
			}

			if (_tuner_art_url == null)
				_tuner_art_url = make_icon_file (ICON_RESOURCE, "mpris-tuner-icon.png");
			return _tuner_art_url;
		} // stock_url


		/**
		 * @brief Draws an icon from the app resources to a PNG in the cache folder.
		 *
		 * @param resource The icon's resource path.
		 * @param file_name Name of the PNG to write.
		 * @return The file's address, or "file:///" if it could not be made.
		 */
		private string make_icon_file (string resource, string file_name)
		{
			if (_cache_dir == null)
				return "file:///";

			try
			{
				// The file name carries the app version, so an upgrade draws the icons again. Within a
				// version the drawn file is reused: rendering a large SVG on every start delays the window.
				var versioned = file_name.replace (".png", @"-$(Application.APP_VERSION).png");
				var file      = File.new_build_filename (_cache_dir, versioned);
				if (file.query_exists () && file.query_info ("standard::size", FileQueryInfoFlags.NONE).get_size () > 0)
					return file.get_uri ();

				var began  = GLib.get_monotonic_time ();
				var pixbuf = new Gdk.Pixbuf.from_resource_at_scale (resource, ICON_SIZE_PX, ICON_SIZE_PX, true);
				pixbuf.save (file.get_path (), "png");
				if (Tuner.debug_enabled ())
					debug (@"[startup] drew MPRIS icon $versioned in $((GLib.get_monotonic_time () - began) / 1000)ms");
				return file.get_uri ();
			} catch (Error e)
			{
				warning (@"Could not make the MPRIS artwork $file_name: $(e.message)");
			}
			return "file:///";
		} // make_icon_file
	} // MprisArtwork
} // Tuner.Services.DBus
