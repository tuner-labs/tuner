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
    
    private Player? _player;
    private Station _station; 
    private Metadata _metadata;
    private Player.State _player_state = Player.State.STOPPED;
    private uint _tape_counter_id = 0;
    private Player.State _last_play_state = Player.State.STOPPED;
    private double _volume_cache = 0.5;
    private uint _debounce_state_id = 0;
    private const uint PLAYING_STATE_DEBOUNCE_MS = 1000;


    construct 
    {
        var app_ref = app();
        if (app_ref != null && app_ref.settings != null)
            _volume_cache = app_ref.settings.volume;
    } // construct


    /** 
     * @brief Process the Player play state changes emitted from gstreamer.
     * 
     * Actions are normalized in controller space to keep stream implementations simple.
     */
    private void set_play_state (Player.State state) 
    {
        var player = _player;
        if (player == null)
            return;
        switch (state) {
            case Player.State.PLAYING:
                {
                    var app_ref = app();
                    if (app_ref != null && app_ref.is_offline)
                    {
                        _play_error = false;
                        player.stop ();
                        player_state = Player.State.STOPPED;
                        break;
                    }
                    _play_error = false;
                    player_state = Player.State.PLAYING;
                }
                break;

            case Player.State.BUFFERING:
            case Player.State.PAUSED:
                {
                    var app_ref = app();
                    if (app_ref != null && app_ref.is_offline)
                    {
                        _play_error = false;
                        player.stop ();
                        player_state = Player.State.STOPPED;
                        break;
                    }
                    _play_error = false;
                    player_state = Player.State.BUFFERING;
                }
                break;

            default :       //  STOPPED:
                {
                    bool network_available = NetworkMonitor.get_default ().get_network_available ();
                    var app_ref = app();
                    bool offline_or_lost_network = (app_ref != null && app_ref.is_offline) || !network_available;

                    if ( _play_error && !offline_or_lost_network )
                    {
                        player_state = Player.State.STOPPED_ERROR;
                    }
                    else
                    {
                        if (offline_or_lost_network)
                            _play_error = false;
                        player_state = Player.State.STOPPED;
                    }
                }
                break;
        } // switch
    } // set_reverse_symbol


    /** 
     * @brief Player State getter/setter
     * 
     * Set by player signal. Does the tape counter emit
     */
     public Player.State player_state { 
        get {
            return _player_state;
        } // get

        private set {
            _player_state = value;
            var app_ref = app();
            if (_station != null && app_ref != null)
                app_ref.events.state_changed_sig(_station, value);

			if (value == Player.State.STOPPED || value == Player.State.STOPPED_ERROR)
			{
				if (_tape_counter_id > 0)
				{
					Source.remove(_tape_counter_id);
					_tape_counter_id = 0;
				}
			}
			else if (value == Player.State.PLAYING)
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
        attach_player (new GstStreamPlayer (stream_url));
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
            case Player.State.PLAYING:
            case Player.State.BUFFERING:
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

    private void attach_player (Player player)
    {
        detach_player ();
        _player = player;
        _player.set_volume_level (_volume_cache);
        _last_play_state = Player.State.STOPPED;
        _debounce_state_id = 0;
        _play_error = false;

        _player.state_changed_sig.connect (on_player_state_changed);
        _player.metadata_changed_sig.connect (on_player_metadata_changed);
        _player.error_sig.connect (on_player_error);

        on_player_state_changed (_player.play_state);
        on_player_metadata_changed (_player.metadata);
    } // attach_player


    private void detach_player ()
    {
        cancel_state_debounce ();
        if (_player != null)
        {
            _player.state_changed_sig.disconnect (on_player_state_changed);
            _player.metadata_changed_sig.disconnect (on_player_metadata_changed);
            _player.error_sig.disconnect (on_player_error);
        }
        _player = null;
    } // detach_player


    private void on_player_state_changed (Player.State state)
    {
        apply_player_state (state, false);
    } // on_player_state_changed


    private void apply_player_state (Player.State state, bool force)
    {
        if (!force && state == _last_play_state)
            return;
        _last_play_state = state;

        if (state == Player.State.PLAYING)
        {
            cancel_state_debounce ();
            set_play_state (Player.State.PLAYING);
            return;
        }

        if (state == Player.State.BUFFERING
            || state == Player.State.PAUSED)
        {
            if (_player_state == Player.State.PLAYING)
            {
                schedule_state_debounce ();
            }
            else
            {
                set_play_state (Player.State.BUFFERING);
            }
            return;
        }

        cancel_state_debounce ();
        set_play_state (Player.State.STOPPED);
    } // apply_player_state


    private void schedule_state_debounce ()
    {
        if (_debounce_state_id > 0)
            return;
        _debounce_state_id = Timeout.add (PLAYING_STATE_DEBOUNCE_MS, () => {
            _debounce_state_id = 0;
            var player = _player;
            if (player == null)
                return Source.REMOVE;
            apply_player_state (player.play_state, true);
            return Source.REMOVE;
        });
    } // schedule_state_debounce


    private void cancel_state_debounce ()
    {
        if (_debounce_state_id > 0)
        {
            Source.remove (_debounce_state_id);
            _debounce_state_id = 0;
        }
    } // cancel_state_debounce

    
    private void on_player_metadata_changed (GLib.HashTable<string, string> metadata)
    {
        if (_player == null || _station == null)
            return;

        if (_metadata.process_tag_table (metadata))
        {
            var app_ref = app();
            if (app_ref != null)
                app_ref.events.metadata_changed_sig (_station, _metadata);
        }
    } // on_player_metadata_changed


    private void on_player_error (string _message)
    {
        _play_error = true;
        set_play_state (Player.State.STOPPED);
    } // on_player_error


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
