/**
 * SPDX-FileCopyrightText: Copyright © 2020-2024 Louis Brauer <louis@brauer.family>
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file DBusMediaPlayer.vala
 */

using Tuner.Controllers;
using Tuner.Ext;
using Tuner.Models;

/**
 * @brief DBusMediaPlayer namespace for handling MPRIS interface integration.
 *
 * Tuner owns org.mpris.MediaPlayer2.io.github.tuner_labs.tuner on the session bus (Flatpak allows this name
 * because it contains the app id). How the Player interface maps onto Tuner:
 *
 *  - Play starts a stopped station and does nothing if playing; Pause and Stop stop the stream, as a live
 *    stream cannot be paused; PlayPause toggles.
 *  - Next turns on jukebox (shuffle) mode, or moves on if it is already on, and is available while online.
 *    Previous returns to the most recent different station in the History, and is available while online
 *    when there is one. Clients are told when either becomes available or unavailable.
 *  - Volume reads and writes the player volume; Rate and its limits are always 1; PlaybackStatus, Shuffle
 *    and the rate limits are read-only.
 *  - Metadata carries a track id (one per station), title, artist and album (the station name), and artwork:
 *    the image the stream provides, else the station favicon once it has loaded, else the Tuner icon (the jukebox icon in jukebox mode) drawn to a PNG in the cache
 *    folder.
 *  - Raise shows the main window; Quit stops playback, saves state and quits, even if "keep playing when the
 *    window is closed" is on. Fullscreen and OpenUri are not supported.
 */
namespace Tuner.Services.DBus 
{

	const string ServerName     = "org.mpris.MediaPlayer2.io.github.tuner_labs.tuner";
	const string ServerPath     = "/org/mpris/MediaPlayer2";
	private bool is_initialized = false;
	private Application? _application = null;

	/**
	 * @brief Initializes and registers the MPRIS DBus service.
	 *
	 * @param application Application context used by DBus handlers.
	 */
	public void initialize (Application application)
	{
		if (is_initialized)
		{
			// App is already running, do nothing
			return;
		}
		_application = application;

		var owner_id = Bus.own_name(
			BusType.SESSION,
			ServerName,
			BusNameOwnerFlags.NONE,
			onBusAcquired,
			() => {
			is_initialized = true;
		},
			() => warning (@"Could not acquire name $ServerName, the DBus interface will not be available")
			);

		if (owner_id == 0)
		{
			warning ("Could not initialize MPRIS session.\n");
		}
	}     // initialize


	void onBusAcquired (DBusConnection conn)
	{
		if (_application == null)
		{
			warning ("DBus initialized without application context");
			return;
		}

		try
		{
			conn.register_object<IMediaPlayer2> (ServerPath, new MediaPlayer (_application));
			conn.register_object<IMediaPlayer2Player> (ServerPath, new MediaPlayerPlayer (conn, _application, _application.player));
		} catch (IOError e)
		{
			warning (@"Could not acquire path $ServerPath: $(e.message)");
			return;
		}
		info (@"DBus Server is now listening on $ServerName $ServerPath…\n");
	}     // onBusAcquired


	/**
	 * @brief MPRIS root object (org.mpris.MediaPlayer2): application identity and window control.
	 */
	public class MediaPlayer : Object, DBus.IMediaPlayer2
	{
		private Application _app;

		/**
		 * @brief Creates the root MPRIS media-player object.
		 *
		 * @param app Application context used for raise/present behavior.
		 */
		public MediaPlayer (Application app)
		{
			Object ();
			_app = app;
		}

		/**
		 * @brief MPRIS Raise: brings the main window to the front.
		 */
		public void raise() throws DBusError, IOError
		{
			debug ("DBus Raise() requested");
			// MPRIS passes no input timestamp, so let GTK use the current time
			if (_app.window != null)
				_app.window.present ();
		}

		/**
		 * @brief MPRIS Quit: stops playback and quits, even when "keep playing" is set.
		 */
		public void quit() throws DBusError, IOError
		{
			debug ("DBus Quit() requested");

			// Quit after the reply has gone back to the caller
			Idle.add (() => {
				_app.quit_cleanly ("MPRIS Quit");
				return Source.REMOVE;
			});
		}

		public bool can_quit {
			get {
				return true;
			}
		}

		public bool can_raise {
			get {
				return true;
			}
		}

		public bool has_track_list {
			get {
				return false;
			}
		}

		public string desktop_entry {
			owned get {
				return ((Gtk.Application)GLib.Application.get_default ()).application_id;
			}
		}

		public string identity {
			owned get {
				return "Tuner";
			}
		}

		public string[] supported_uri_schemes {
			owned get {
				return {};     // OpenUri is not supported
			}
		}

		public string[] supported_mime_types {
			owned get {
				return {"audio/mp3","audio/aac","audio/x-vorbis+ogg","audio/x-flac","audio/x-wav","audio/x-m4a","audio/mpeg"};
			}
		}

		public bool fullscreen {
			get { return false; }
			set { }     // Fullscreen is not supported
		}
		public bool can_set_fullscreen {
			get {
				return false;
			}
		}
	}     // MediaPlayer


	/**
	 * @brief MPRIS player object (org.mpris.MediaPlayer2.Player): playback control and now-playing metadata.
	 */
	public class MediaPlayerPlayer : Object, DBus.IMediaPlayer2Player
	{
		[DBus (visible = false)]
		private Station _station;
		private string _playback_status                       = "Stopped";
		private string _current_title                         = "";
		private string _current_artist                        = "Tuner";
		private MprisArtwork _artwork;                                      // Chooses the artwork clients show
		private uint _update_metadata_source                  = 0;
		private uint _send_property_source                    = 0;
		private const string NO_TRACK = "/org/mpris/MediaPlayer2/TrackList/NoTrack";
		private const string TRACK_PATH_PREFIX = "/io/github/tuner_labs/tuner/station/";
		private HashTable<string,Variant> _metadata           = new HashTable<string,Variant> (str_hash, str_equal);
		private HashTable<string,Variant> _changed_properties = null;

		[DBus (visible = false)]
		public unowned DBusConnection conn { get; construct set; }

		private const string INTERFACE_NAME = "org.mpris.MediaPlayer2.Player";
		private Application _app;
		private PlayerController _player;

		/**
		 * @brief Creates the MPRIS player interface object.
		 *
		 * @param conn DBus connection used to emit property changes.
		 * @param app Application context used for app-level signals.
		 * @param player Player controller used for playback and metadata.
		 */
		public MediaPlayerPlayer (DBusConnection conn, Application app, PlayerController player)
		{
			Object (conn: conn);
			_app = app;
			_player = player;
			_metadata.set ("mpris:trackid", new Variant.object_path (NO_TRACK));   // Required by MPRIS even with nothing playing
			_artwork = new MprisArtwork (_app.cache_dir);
			_artwork.changed.connect (() => { update_metadata (); trigger_metadata_update (); });
			_metadata.set ("mpris:artUrl", _artwork.url ());

			_app.events.player_state_changed_sig.connect ((station, state) =>
			{
				update_navigation_flags ();

				// A station that stops on an error shows the error icon until it plays again or another station is chosen
				var in_error = state == StreamPlayer.State.STOPPED_ERROR;
				if (in_error != _artwork.in_error)
				{
					_artwork.in_error = in_error;
					update_metadata ();
					trigger_metadata_update ();
				}

				switch (state)
				{
					case StreamPlayer.State.PLAYING:
					case StreamPlayer.State.BUFFERING:
						set_playback_status ("Playing");
						break;
					case StreamPlayer.State.PAUSED:
						set_playback_status ("Paused");
						break;
					default:
						set_playback_status ("Stopped");
						break;
				}
			});


			// A new station starts from its own details. Streams that send no tags never raise a metadata
			// event, so without this the previous station's title and artwork would stay up.
			_app.events.station_changed_sig.connect ((station) =>
			{
				_station         = station;
				_current_title   = station.name;
				_current_artist  = station.name;
				_artwork.station_changed (station);
				update_metadata ();
				trigger_metadata_update ();
			});

			_app.events.playback_metadata_changed_sig.connect (( station, metadata) =>
			{				
				_station         = station;
				_current_title   = station.name;
				_current_artist  = station.name;
				_artwork.metadata_changed (station, metadata.get_image_url ());
				_current_title  = (metadata.title != null && metadata.title != "") ? metadata.title : _station.name;
				_current_artist = (metadata.artist != null && metadata.artist != "") ? metadata.artist : _station.name;
				update_metadata ();
				trigger_metadata_update ();
			});

			_app.events.shuffle_mode_sig.connect ((shuffle) =>
			{
				_shuffle        = shuffle;
				_artwork.shuffle = shuffle;
				queue_property_for_notification ("Shuffle", new Variant.boolean (shuffle));
				update_navigation_flags ();

				// A station showing the stock icon switches between the Tuner and jukebox icons
				if (_artwork.is_stock_icon ())
				{
					update_metadata ();
					trigger_metadata_update ();
				}
			});

			// Next and Previous depend on connectivity and the station history
			_app.events.connectivity_changed_sig.connect ((is_online) => { update_navigation_flags (); });
			_app.history.entry_added_sig.connect ((entry) => { update_navigation_flags (); });
			_app.history.entry_removed_sig.connect ((entry) => { update_navigation_flags (); });
			_app.history.cleared_sig.connect (() => { update_navigation_flags (); });

			_app.events.volume_changed_sig.connect ((volume) =>
			{
				queue_property_for_notification ("Volume", new Variant.double (volume));
			});
		} // MediaPlayerPlayer


		private void update_metadata ()
		{
			//  debug ("DBus metadata requested");
			// Each station gets its own track id; object path elements allow only letters, digits and _
			var track_id = _station != null
				? TRACK_PATH_PREFIX + _station.stationuuid.replace ("-", "_")
				: NO_TRACK;
			_metadata.set ("mpris:trackid", new Variant.object_path (track_id));
			_metadata.set ("xesam:title", _current_title);
			_metadata.set ("xesam:artist", get_simple_string_array  (_current_artist));
			_metadata.set ("xesam:album", _station != null ? _station.name : "");   // Always shows which station is playing

			// With no stream image or favicon, this is the Tuner icon, which also replaces any previous station's image
			_metadata.set ("mpris:artUrl", _artwork.url ());
		} // update_metadata


		/**
		 * @brief MPRIS Next: puts Tuner in jukebox (shuffle) mode, or moves on if it already is.
		 *
		 * Does the same as double-clicking Jukebox in the sidebar.
		 */
		public void next() throws DBusError, IOError
		{
			if (!can_go_next)
				return;

			_app.jukebox.enable ();
			_app.events.shuffle_mode_sig (true);
		}

		/**
		 * @brief MPRIS Previous: goes back to the station that played before this one.
		 */
		public void previous() throws DBusError, IOError
		{
			if (_app.is_offline || _app.window == null)
				return;

			var station = find_previous_station ();
			if (station != null)
				_app.window.handle_play_station (station);
		}


		/**
		 * @brief The most recent station in the history that is not the current one, or null.
		 *
		 * Going back again returns to the station just left, like a "last channel" button.
		 */
		private Station? find_previous_station ()
		{
			var current = _player.station;
			var entries = _app.history.entries;
			for (int index = entries.size - 1; index >= 0; index--)
			{
				var candidate = entries[index].station;
				if (current == null || candidate.stationuuid != current.stationuuid)
					return candidate;
			}
			return null;
		}


		/**
		 * @brief Tells clients when Next or Previous has become available or unavailable.
		 */
		private void update_navigation_flags ()
		{
			bool next_now     = can_go_next;
			bool previous_now = can_go_previous;

			if (next_now != _last_can_go_next)
			{
				_last_can_go_next = next_now;
				queue_property_for_notification ("CanGoNext", new Variant.boolean (next_now));
			}
			if (previous_now != _last_can_go_previous)
			{
				_last_can_go_previous = previous_now;
				queue_property_for_notification ("CanGoPrevious", new Variant.boolean (previous_now));
			}
		}

		/**
		 * @brief MPRIS Pause: a live stream cannot be paused, so this stops it.
		 */
		public void pause() throws DBusError, IOError
		{
			if (_player.player_state == StreamPlayer.State.PLAYING
				|| _player.player_state == StreamPlayer.State.BUFFERING)
				_player.stop ();
		}

		/**
		 * @brief MPRIS PlayPause: toggles playback.
		 */
		public void play_pause() throws DBusError, IOError
		{
			//  debug ("DBus PlayPause() requested");
			_player.play_pause();
		}

		/**
		 * @brief MPRIS Stop: stops playback.
		 */
		public void stop() throws DBusError, IOError
		{
			//  debug ("DBus stop() requested");
			_player.stop();
		}

		/**
		 * @brief MPRIS Play: starts playback; does nothing if it is already playing.
		 */
		public void play() throws DBusError, IOError
		{
			if (_player.player_state != StreamPlayer.State.PLAYING
				&& _player.player_state != StreamPlayer.State.BUFFERING)
				_player.play_pause ();
		}

		/**
		 * @brief MPRIS Seek: not supported for live streams, does nothing.
		 */
		public void seek(int64 Offset) throws DBusError, IOError
		{
			//  debug ("DBus Seek() requested");
		}

		/**
		 * @brief MPRIS SetPosition: not supported for live streams, does nothing.
		 */
		public void set_position(ObjectPath TrackId, int64 Position) throws DBusError, IOError
		{
			//  debug ("DBus SetPosition() requested");
		}

		/**
		 * @brief MPRIS OpenUri: not supported, does nothing.
		 */
		public void open_uri(string uri) throws DBusError, IOError
		{
			//  debug ("DBus OpenUri() requested");
		}

		public string playback_status {
			owned get {
				return _playback_status;
			}
		}

		/**
		 * @brief Records a new playback status and tells clients. Not settable over D-Bus.
		 */
		private void set_playback_status (string status)
		{
			_playback_status = status;
			trigger_metadata_update ();
		}

		public string loop_status {
			owned get {
				return "None";
			}
		}

		// A live stream always plays at normal speed
		public double rate {
			get { return 1.0; }
			set { }
		}
		private bool _shuffle = false;
		private bool _last_can_go_next = false;
		private bool _last_can_go_previous = false;
		public bool shuffle {
			get { return _shuffle; }
		}

		public HashTable<string, Variant>? metadata {
			owned get {
				return _metadata;
			}
		}
		public double volume {
			get { return _player.volume; }
			set { _player.volume = double.min (double.max (value, 0.0), 1.0); }
		}
		public int64 position { get; }
		public double minimum_rate { get { return 1.0; } }
		public double maximum_rate { get { return 1.0; } }

		public bool can_go_next {
			get {
				// Next starts or advances the jukebox, which needs a connection
				return !_app.is_offline;
			}
		}

		public bool can_go_previous {
			get {
				// There has to be an earlier, different station to go back to
				return !_app.is_offline && find_previous_station () != null;
			}
		}

		public bool can_play {
			get {
				//  debug ("CanPlay() requested");
				return _player.can_play ();
			}
		}
		public bool can_pause {
			get {
				// Pause stops the stream
				return true;
			}
		}
		public bool can_seek {  get; }

		public bool can_control {
			get {
				//  debug ("CanControl() requested");
				return true;
			}
		}

		private void trigger_metadata_update ()
		{
			if (_update_metadata_source != 0)
			{
				Source.remove (_update_metadata_source);
			}

			_update_metadata_source = Timeout.add (300, () => {
				Variant variant = playback_status;

				queue_property_for_notification ("PlaybackStatus", variant);
				queue_property_for_notification ("Metadata", metadata);
				_update_metadata_source = 0;
				return false;
			});
		}

		private void queue_property_for_notification (string property, Variant val)
		{
			if (_changed_properties == null)
			{
				_changed_properties = new HashTable<string, Variant> (str_hash, str_equal);
			}

			_changed_properties.insert (property, val);

			if (_send_property_source == 0)
			{
				_send_property_source = Idle.add (send_property_change);
			}
		}

		private bool send_property_change ()
		{
			if (_changed_properties == null)
			{
				return false;
			}

			var builder             = new VariantBuilder (VariantType.ARRAY);
			var invalidated_builder = new VariantBuilder (new VariantType ("as"));

			foreach (string name in _changed_properties.get_keys ())
			{
				Variant variant = _changed_properties.lookup (name);
				builder.add ("{sv}", name, variant);
			}

			_changed_properties = null;

			try
			{
				conn.emit_signal (null,
				                  "/org/mpris/MediaPlayer2",
				                  "org.freedesktop.DBus.Properties",
				                  "PropertiesChanged",
				                  new Variant ("(sa{sv}as)",
				                               INTERFACE_NAME,
				                               builder,
				                               invalidated_builder)
				                  );
			} catch (Error e)
			{
				if (Tuner.debug_enabled ())
					debug (@"Could not send MPRIS property change: $(e.message)");
			}
			_send_property_source = 0;
			return false;
		}

		private static string[] get_simple_string_array (string? text)
		{
			if (text == null)
			{
				return new string[0];
			}
			string[] array = new string[0];
			array += text;
			return array;
		}
	}     // MediaPlayerPlayer
}
