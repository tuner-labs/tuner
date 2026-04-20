/**
 * SPDX-FileCopyrightText: Copyright © 2020-2024 Louis Brauer <louis@brauer.family>
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file PlayerController.vala
 */

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
    private const bool TRACE_METADATA_PATH = false;

    private const uint CLICK_INTERVAL_IN_SECONDS = 606;  // tape counter timer - 10 mins plus 1%
    private const uint PLAYING_STATE_DEBOUNCE_MS = 1000;

    public bool play_error { get { return _play_error; } }
    public string? play_error_message { get { return _play_error_message; } }


    /** The error received when playing, if any */
    private bool _play_error = false;
    private string? _play_error_message = null;

    
    private StreamPlayer? _player;
    private Station _station; 
    //private StreamMetadata _metadata;
    private StreamPlayer.State _player_state = StreamPlayer.State.STOPPED;
    private StreamPlayer.State _last_play_state = StreamPlayer.State.STOPPED;
    private double _volume_cache = 0.5;
    private uint _debounce_state_id = 0;

    private uint _tape_counter_id = 0;


    //  construct 
    //  {
    //      _volume_cache = app().settings.volume;
    //  } // construct


    /**
     * @brief Process play state changes emitted from the stream player.
     *
     * Actions are normalized in controller space to keep stream implementations simple.
     *
     * @param state The stream player's reported state.
     */
    private void set_play_state (StreamPlayer.State state) 
    {
        if (_player == null)
            return;
        switch (state) {
            case StreamPlayer.State.PLAYING:
                {
                    if (app().is_offline)
                    {
                        clear_play_error ();
                        _player.stop ();
                        player_state = StreamPlayer.State.STOPPED;
                        break;
                    }
                    clear_play_error ();
                    player_state = StreamPlayer.State.PLAYING;
                }
                break;

            case StreamPlayer.State.BUFFERING:
            case StreamPlayer.State.PAUSED:
                {
                    if ( app().is_offline)
                    {
                        clear_play_error ();
                        _player.stop ();
                        player_state = StreamPlayer.State.STOPPED;
                        break;
                    }
                    clear_play_error ();
                    player_state = StreamPlayer.State.BUFFERING;
                }
                break;

            default :       //  STOPPED:
                {
                    bool network_available = NetworkMonitor.get_default ().get_network_available ();
                    
                    bool offline_or_lost_network = app().is_offline || !network_available;

                    if ( _play_error && !offline_or_lost_network )
                    {
                        player_state = StreamPlayer.State.STOPPED_ERROR;
                    }
                    else
                    {
                        if (offline_or_lost_network)
                            clear_play_error ();
                        player_state = StreamPlayer.State.STOPPED;
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
     public StreamPlayer.State player_state { 
        get {
            return _player_state;
        } // get

        private set {
            _player_state = value;
            
            if (_station != null )
                app().events.player_state_changed_sig(_station, value);

			if (value == StreamPlayer.State.STOPPED || value == StreamPlayer.State.STOPPED_ERROR)
			{
				if (_tape_counter_id > 0)
				{
					Source.remove(_tape_counter_id);
					_tape_counter_id = 0;
				}
			}
			else if (value == StreamPlayer.State.PLAYING)
			{
				_tape_counter_id = Timeout.add_seconds_full(Priority.LOW, CLICK_INTERVAL_IN_SECONDS, () =>
				{
					if (_station == null)
						return Source.REMOVE;
					app().events.tape_counter_sig(_station);
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
            
                app().events.volume_changed_sig (value);
                if (app().settings != null)
                    app().settings.volume = value;
        }
    } // volume


    /**
    * @brief Plays the specified station.
    *
    * The player will crossfade from the current station to the new one.
    * The current player is detached and a new one created and attached
    *
    * @param station The station to play.
    */
	public void play_station (Station station)
	{
        var previous_player = _player;
        if (previous_player != null)
            detach_player ();

        _station = station;
        string stream_url = (_station.urlResolved != null && _station.urlResolved != "") ? _station.urlResolved : _station.url;

        _volume_cache = app().settings.volume;
        attach_player (Tuner.create_stream_player (stream_url));
        clear_play_error ();
        _station.track_listen ();
        app().events.station_changed_sig (_station);
        if (previous_player != null && _player != null)
        {
            previous_player.crossfade_to (_player, _volume_cache);
            return;
        }
		Timeout.add (500, () =>
		// Wait a half of a second to play the station to help flush metadata
		{
            if (_player != null)
			    _player.play ();
			return Source.REMOVE;
		});
	} // play_station


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
            case StreamPlayer.State.PLAYING:
            case StreamPlayer.State.BUFFERING:
                if (_player != null)
                    _player.stop ();
                break;
            default:
                clear_play_error ();
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

    /**
     * @brief Connects a new player instance and initializes controller state.
     *
     * @param player The player instance to attach.
     */
    private void attach_player (StreamPlayer player)
    {
        detach_player ();
        _player = player;
        _player.set_volume_level (_volume_cache);
        _last_play_state = StreamPlayer.State.STOPPED;
        _debounce_state_id = 0;
        clear_play_error ();

        _player.play_state_changed_sig.connect (on_player_state_changed);
        _player.stream_metadata_changed_sig.connect (on_player_metadata_changed);
        _player.playback_error_sig.connect (on_player_error);

        on_player_state_changed (_player.play_state);
        on_player_metadata_changed ();
    } // attach_player


    /**
     * @brief Disconnects the current player instance and clears controller state.
     */
    private void detach_player ()
    {
        cancel_state_debounce ();
        if (_player != null)
        {
            _player.play_state_changed_sig.disconnect (on_player_state_changed);
            _player.stream_metadata_changed_sig.disconnect (on_player_metadata_changed);
            _player.playback_error_sig.disconnect (on_player_error);
        }
        _player = null;
    } // detach_player


    /**
     * @brief Handles state change signals from the player.
     *
     * @param state The new player state.
     */
    private void on_player_state_changed (StreamPlayer.State state)
    {
        apply_player_state (state, false);
    } // on_player_state_changed


    /**
     * @brief Applies a player state change with optional debounce override.
     *
     * @param state The player state to apply.
     * @param force True to apply even if the state matches the last seen value.
     */
    private void apply_player_state (StreamPlayer.State state, bool force)
    {
        if (!force && state == _last_play_state)
            return;
        _last_play_state = state;

        if (state == StreamPlayer.State.PLAYING)
        {
            cancel_state_debounce ();
            set_play_state (StreamPlayer.State.PLAYING);
            return;
        }

        if (state == StreamPlayer.State.BUFFERING
            || state == StreamPlayer.State.PAUSED)
        {
            if (_player_state == StreamPlayer.State.PLAYING)
            {
                schedule_state_debounce ();
            }
            else
            {
                set_play_state (StreamPlayer.State.BUFFERING);
            }
            return;
        }

        cancel_state_debounce ();
        set_play_state (StreamPlayer.State.STOPPED);
    } // apply_player_state


    /**
     * @brief Schedules a short debounce before applying a non-playing state.
     */
    private void schedule_state_debounce ()
    {
        if (_debounce_state_id > 0)
            return;
        _debounce_state_id = Timeout.add (PLAYING_STATE_DEBOUNCE_MS, () => 
            {
                _debounce_state_id = 0;
                var player = _player;
                if (player == null)
                    return Source.REMOVE;
                apply_player_state (player.play_state, true);
                return Source.REMOVE;
            });
    } // schedule_state_debounce


    /**
     * @brief Cancels any pending debounce timer.
     */
    private void cancel_state_debounce ()
    {
        if (_debounce_state_id > 0)
        {
            Source.remove (_debounce_state_id);
            _debounce_state_id = 0;
        }
    } // cancel_state_debounce

    
    /**
     * @brief Handles updated metadata from the player.
     *
     * @param metadata The metadata table provided by the player.
     */
    private void on_player_metadata_changed ()
    {
        if (_player == null || _station == null)
            return;

        if (TRACE_METADATA_PATH)
        {
            stdout.printf (
                "[TRACE][PlayerController] emit playback_metadata station=%s title='%s' pretty_len=%u\n",
                _station.stationuuid,
                _player.stream_metadata.title,
                _player.stream_metadata.pretty_print.length
            );
        }

        app().events.playback_metadata_changed_sig (_station, _player.stream_metadata);

    } // on_player_metadata_changed


    /**
     * @brief Handles playback errors reported by the player.
     *
     * @param _message The error message reported by the player.
     */
    private void on_player_error (string _message)
    {
        _play_error = true;
        _play_error_message = _message;
        set_play_state (StreamPlayer.State.STOPPED_ERROR);
    } // on_player_error


    /**
     * @brief Clears stored playback error state and message.
     */
    private void clear_play_error ()
    {
        _play_error = false;
        _play_error_message = null;
    } // clear_play_error


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
