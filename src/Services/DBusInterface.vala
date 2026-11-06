/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2020-2022 Louis Brauer <louis@brauer.family>
 */


/**
 * @brief D-Bus binding for the MPRIS org.mpris.MediaPlayer2.Player interface.
 */
[DBus (name = "org.mpris.MediaPlayer2.Player", timeout = 120000)]
public interface Tuner.Services.DBus.IMediaPlayer2Player : GLib.Object {

	[DBus (name = "Next")]
	public abstract void next() throws DBusError, IOError;

	[DBus (name = "Previous")]
	public abstract void previous() throws DBusError, IOError;

	[DBus (name = "Pause")]
	public abstract void pause() throws DBusError, IOError;

	[DBus (name = "PlayPause")]
	public abstract void play_pause() throws DBusError, IOError;

	[DBus (name = "Stop")]
	public abstract void stop() throws DBusError, IOError;

	[DBus (name = "Play")]
	public abstract void play() throws DBusError, IOError;

	[DBus (name = "Seek")]
	public abstract void seek(int64 Offset) throws DBusError, IOError;

	[DBus (name = "SetPosition")]
	public abstract void set_position(ObjectPath TrackId, int64 Position) throws DBusError, IOError;

	[DBus (name = "OpenUri")]
	public abstract void open_uri(string Uri) throws DBusError, IOError;

	[DBus (name = "Seeked")]
	public signal void seeked(int64 Position);

	[DBus (name = "PlaybackStatus")]
	public abstract string playback_status { owned get; }

	[DBus (name = "LoopStatus")]
	public abstract string loop_status { owned get; }

	[DBus (name = "Rate")]
	public abstract double rate {  get; set; }

	[DBus (name = "Shuffle")]
	public abstract bool shuffle {  get; }

	[DBus (name = "Metadata")]
	public abstract HashTable<string, Variant>? metadata { owned get; }

	[DBus (name = "Volume")]
	public abstract double volume {  get; set; }

	[DBus (name = "Position")]
	public abstract int64 position {
	    get;
	}

	[DBus (name = "MinimumRate")]
	public abstract double minimum_rate {  get; }

	[DBus (name = "MaximumRate")]
	public abstract double maximum_rate {  get; }

	[DBus (name = "CanGoNext")]
	public abstract bool can_go_next {  get; }

	[DBus (name = "CanGoPrevious")]
	public abstract bool can_go_previous {  get; }

	[DBus (name = "CanPlay")]
	public abstract bool can_play {  get; }

	[DBus (name = "CanPause")]
	public abstract bool can_pause {  get; }

	[DBus (name = "CanSeek")]
	public abstract bool can_seek {  get; }

	[DBus (name = "CanControl")]
	public abstract bool can_control {  get; }
}

/**
 * @brief D-Bus binding for the MPRIS org.mpris.MediaPlayer2 root interface.
 */
[DBus (name = "org.mpris.MediaPlayer2", timeout = 120000)]
public interface Tuner.Services.DBus.IMediaPlayer2 : GLib.Object {

	[DBus (name = "Raise")]
	public abstract void raise() throws DBusError, IOError;

	[DBus (name = "Quit")]
	public abstract void quit() throws DBusError, IOError;

	[DBus (name = "CanQuit")]
	public abstract bool can_quit {  get; }

	[DBus (name = "Fullscreen")]
	public abstract bool fullscreen {  get; set; }

	[DBus (name = "CanSetFullscreen")]
	public abstract bool can_set_fullscreen {  get; }

	[DBus (name = "CanRaise")]
	public abstract bool can_raise {  get; }

	[DBus (name = "HasTrackList")]
	public abstract bool has_track_list {  get; }

	[DBus (name = "Identity")]
	public abstract string identity { owned get; }

	[DBus (name = "DesktopEntry")]
	public abstract string desktop_entry { owned get; }

	[DBus (name = "SupportedUriSchemes")]
	public abstract string[] supported_uri_schemes { owned get; }

	[DBus (name = "SupportedMimeTypes")]
	public abstract string[] supported_mime_types { owned get; }
}
