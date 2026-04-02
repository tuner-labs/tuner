/**
 * SPDX-FileCopyrightText: Copyright © 2020-2024 Louis Brauer <louis@brauer.family>
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file PlayerController.vala
 */

using Tuner.Ext;
using Tuner.Models;

/**
 * @class Tuner.PlayerController
 * @brief Manages the playback of radio stations.
 *
 * This class handles the player state, volume control, and metadata extraction
 * from the media stream. It emits signals when the station, state, title,
 * or volume changes.
 */
public class Tuner.Controllers.PlayerController : GLib.Object 
{
    /** The error received when playing, if any */
    private bool _play_error = false;
    public bool play_error { get { return _play_error; } }

    private const uint CLICK_INTERVAL_IN_SECONDS = 606;  // tape counter timer - 10 mins plus 1%
    
    private PlayerInterface? _player;
    private Station _station; 
    private Metadata _metadata;
    private PlayerInterface.State _player_state = PlayerInterface.State.STOPPED;
    private uint _tape_counter_id = 0;
    private uint _player_poll_id = 0;
    private uint _metadata_poll_id = 0;
    private StreamStatus _last_status = StreamStatus.IDLE;
    private PlayerInterface.State _last_play_state = PlayerInterface.State.STOPPED;
    private double _volume_cache = 0.5;
    private int64 _last_playing_usec = 0;
    private const int64 PLAYING_STATE_DEBOUNCE_USEC = 750000;


    construct 
    {
        var app_ref = app();
        if (app_ref != null && app_ref.settings != null)
            _volume_cache = app_ref.settings.volume;
    } // construct


    /** 
     * @brief Process the Player play state changes emitted from gstreamer.
     * 
     * Actions are set in a separate thread as attempting UI interaction 
     * on the gstreamer signal results in a seg fault
     */
    private void set_play_state (PlayerInterface.State state) 
    {
        var player = _player;
        if (player == null)
            return;
        switch (state) {
            case PlayerInterface.State.PLAYING:
                {
                    var app_ref = app();
                    if (app_ref != null && app_ref.is_offline)
                    {
                        _play_error = false;
                        player.stop ();
                        player_state = PlayerInterface.State.STOPPED;
                        break;
                    }
                    _play_error = false;
                    player_state = PlayerInterface.State.PLAYING;
                }
                break;

            case PlayerInterface.State.BUFFERING:
            case PlayerInterface.State.PAUSED:
                {
                    var app_ref = app();
                    if (app_ref != null && app_ref.is_offline)
                    {
                        _play_error = false;
                        player.stop ();
                        player_state = PlayerInterface.State.STOPPED;
                        break;
                    }
                    _play_error = false;
                    player_state = PlayerInterface.State.BUFFERING;
                }
                break;

            default :       //  STOPPED:
                {
                    bool network_available = NetworkMonitor.get_default ().get_network_available ();
                    var app_ref = app();
                    bool offline_or_lost_network = (app_ref != null && app_ref.is_offline) || !network_available;

                    if ( _play_error && !offline_or_lost_network )
                    {
                        player_state = PlayerInterface.State.STOPPED_ERROR;
                    }
                    else
                    {
                        if (offline_or_lost_network)
                            _play_error = false;
                        player_state = PlayerInterface.State.STOPPED;
                    }
                }
                break;
        }
    } // set_reverse_symbol


    /** 
     * @brief Player State getter/setter
     * 
     * Set by player signal. Does the tape counter emit
     */
     public PlayerInterface.State player_state { 
        get {
            return _player_state;
        } // get

        private set {
            _player_state = value;
            var app_ref = app();
            if (_station != null && app_ref != null)
                app_ref.events.state_changed_sig(_station, value);

			if (value == PlayerInterface.State.STOPPED || value == PlayerInterface.State.STOPPED_ERROR)
			{
				if (_tape_counter_id > 0)
				{
					Source.remove(_tape_counter_id);
					_tape_counter_id = 0;
				}
			}
			else if (value == PlayerInterface.State.PLAYING)
			{
				_tape_counter_id = Timeout.add_seconds_full(Priority.LOW, CLICK_INTERVAL_IN_SECONDS, () =>
				{
					if (_station == null)
						return Source.REMOVE;
                    if (app_ref != null)
					    app_ref.events.tape_counter_sig(_station);
					return Source.CONTINUE;
				});
			}
		} // set
	} // player_state


    /** 
     * @brief Station
     * @return The current station being played.
     */
    public Station station {
        get {
            return _station;
        }
        set {
            if ( ( _station == null ) ||  ( _station != value ) )
            {
                _metadata =  new Metadata();
                _station = value;
                play_station (_station);
            }
        }
    } // station


    /** 
     * @brief Volume
     * @return The current volume of the player.
     */
    public double volume {
        get { return _player != null ? _player.volume : _volume_cache; }
        set {
            _volume_cache = value;
            if (_player != null)
                _player.set_volume_level (value);
            var app_ref = app();
            if (app_ref != null)
            {
                app_ref.events.volume_changed_sig (value);
                if (app_ref.settings != null)
                    app_ref.settings.volume = value;
            }
        }
    } // volume


    /**
    * @brief Plays the specified station.
    *
    * @param station The station to play.
    */
	public void play_station (Station station)
	{
        if (_player != null)
		    _player.stop ();
        detach_player ();
        _station = station;
        var app_ref = app();
        if (app_ref != null)
            app_ref.events.station_changed_sig (_station);
        string stream_url = (_station.urlResolved != null && _station.urlResolved != "") ? _station.urlResolved : _station.url;
        if (app_ref != null && app_ref.settings != null)
            _volume_cache = app_ref.settings.volume;
        attach_player (new StreamPlayer (stream_url));
		_play_error = false;
		Timeout.add (500, () =>
		// Wait a half of a second to play the station to help flush metadata
		{
            if (_player != null)
			    _player.play ();
			return Source.REMOVE;
		});
	}     // play_station


    /**
     * @brief Checks if the player has a station to play.
     *
     * @return True if a station is ready to be played
     */
    public bool can_play () {
        return _station != null;
    } // can_play


    /**
     * @brief Toggles play/pause state of the player.
     */
     public void play_pause () {
        switch (_player_state) {
            case PlayerInterface.State.PLAYING:
            case PlayerInterface.State.BUFFERING:
                if (_player != null)
                    _player.stop ();
                break;
            default:
                _play_error = false;
                if (_player != null)
                    _player.play ();
                break;
        }
    } // play_pause


    /**
     * @brief Stops the player
     *
     */
    public void stop () {
        if (_player != null)
            _player.stop ();
    } // stop

    private void attach_player (PlayerInterface player)
    {
        detach_player ();
        _player = player;
        _player.set_volume_level (_volume_cache);
        _last_status = _player.status;
        _last_play_state = _player.play_state;

        _player_poll_id = Timeout.add (200, () => {
            if (_player == null)
                return Source.REMOVE;
            update_player_state ();
            return Source.CONTINUE;
        });

        _metadata_poll_id = Timeout.add (500, () => {
            if (_player == null)
                return Source.REMOVE;
            update_metadata ();
            return Source.CONTINUE;
        });
    } // attach_player


    private void detach_player ()
    {
        if (_player_poll_id > 0)
        {
            Source.remove (_player_poll_id);
            _player_poll_id = 0;
        }
        if (_metadata_poll_id > 0)
        {
            Source.remove (_metadata_poll_id);
            _metadata_poll_id = 0;
        }
        _player = null;
    } // detach_player


    private void update_player_state ()
    {
        var player = _player;
        if (player == null)
            return;

        if (player.status == _last_status && player.play_state == _last_play_state)
            return;

        _last_status = player.status;
        _last_play_state = player.play_state;

        if (player.status == StreamStatus.ERROR)
        {
            _play_error = true;
            set_play_state (PlayerInterface.State.STOPPED);
            return;
        }

        if (player.play_state == PlayerInterface.State.PLAYING)
        {
            _last_playing_usec = GLib.get_monotonic_time ();
            set_play_state (PlayerInterface.State.PLAYING);
        }
        else if (player.play_state == PlayerInterface.State.BUFFERING
            || player.play_state == PlayerInterface.State.PAUSED)
        {
            var now = GLib.get_monotonic_time ();
            if (player.status == StreamStatus.PLAYING
                && _last_playing_usec > 0
                && (now - _last_playing_usec) < PLAYING_STATE_DEBOUNCE_USEC)
            {
                set_play_state (PlayerInterface.State.PLAYING);
            }
            else
            {
                set_play_state (PlayerInterface.State.BUFFERING);
            }
        }
        else
        {
            _last_playing_usec = 0;
            set_play_state (PlayerInterface.State.STOPPED);
        }
    } // update_player_state

    
    private void update_metadata ()
    {
        if (_player == null || _station == null)
            return;

        if (_metadata.process_tag_table (_player.metadata))
        {
            var app_ref = app();
            if (app_ref != null)
                app_ref.events.metadata_changed_sig (_station, _metadata);
        }
    } // update_metadata


    /**
     * Shuffles the current playlist.
     *
     * This method randomizes the order of the tracks in the current playlist.
     */
	public void shuffle ()
	{
		app().events.shuffle_requested_sig();
	} // shuffle
} // PlayerController
