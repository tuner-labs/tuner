/**
 * SPDX-FileCopyrightText: Copyright © 2020-2024 Louis Brauer <louis@brauer.family>
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file PlayerController.vala
 */

using Gst;
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
    /**
     * @brief the Tuner play state
     *
     * Using our own play state keeps gstreamer deps out of the rest of the code
     */
    public enum Is {
        BUFFERING,
        PAUSED,
        PLAYING,
        STOPPED,        
        STOPPED_ERROR
    } // Is

 
    /** The error received when playing, if any */
    private bool _play_error = false;
    public bool play_error { get { return _play_error; } }

    private const uint CLICK_INTERVAL_IN_SECONDS = 606;  // tape counter timer - 10 mins plus 1%
    
    private Player _player;
    private Station _station; 
    private Metadata _metadata;
    private Is _player_state;
    private string _player_state_name;
    private uint _tape_counter_id = 0;


    construct 
    {
        _player = new Player (null, null);

        _player.error.connect ((error) => 
        // There was an error playing the stream
        {
            Gdk.threads_add_idle (() => {
                _play_error = true;
                return false;
            });
        });

		_player.media_info_updated.connect ((obj) =>
		// Stream metadata received
		{
			if (_metadata.process_media_info_update (obj))
				app().events.metadata_changed_sig (_station, _metadata);
		});

        _player.volume_changed.connect ((obj) => 
        // Volume changed
        {
            app().events.volume_changed_sig(obj.volume);
            app().settings.volume =  obj.volume;
        });

        _player.state_changed.connect ((state) => 
        // Play state changed
        {
            // Don't forward flickering between playing and buffering
            if (    !(state == PlayerState.PLAYING && state == PlayerState.BUFFERING) 
                && (_player_state_name != state.get_name ())) 
            {
                _player_state_name = state.get_name ();
                set_play_state (state.get_name ());
            }
        });
    } // construct


    /** 
     * @brief Process the Player play state changes emitted from gstreamer.
     * 
     * Actions are set in a separate thread as attempting UI interaction 
     * on the gstreamer signal results in a seg fault
     */
    private void set_play_state (string state) 
    {
        switch (state) {
            case "playing":
                Gdk.threads_add_idle (() => {
                    if (app().is_offline)
                    {
                        _play_error = false;
                        _player.stop ();
                        player_state = Is.STOPPED;
                        return false;
                    }
                    _play_error = false;
                    player_state = Is.PLAYING;
                    return false;
                });
                break;

            case "buffering":            
                Gdk.threads_add_idle (() => {
                    if (app().is_offline)
                    {
                        _play_error = false;
                        _player.stop ();
                        player_state = Is.STOPPED;
                        return false;
                    }
                    _play_error = false;
                    player_state = Is.BUFFERING;
                    return false;
                });
                break;

            default :       //  STOPPED:
                Gdk.threads_add_idle (() => {
                    bool network_available = NetworkMonitor.get_default ().get_network_available ();
                    bool offline_or_lost_network = app().is_offline || !network_available;

                    if ( _play_error && !offline_or_lost_network )
                    {
                        player_state = Is.STOPPED_ERROR;
                    }
                    else
                    {
                        if (offline_or_lost_network)
                            _play_error = false;
                        player_state = Is.STOPPED;
                    }
                    return false;
                });
                break;
        }
    } // set_reverse_symbol


    /** 
     * @brief Player State getter/setter
     * 
     * Set by player signal. Does the tape counter emit
     */
     public Is player_state { 
        get {
            return _player_state;
        } // get

        private set {
            _player_state = value;
            if (_station != null)
                app().events.state_changed_sig(_station, value);

			if (value == Is.STOPPED || value == Is.STOPPED_ERROR)
			{
				if (_tape_counter_id > 0)
				{
					Source.remove(_tape_counter_id);
					_tape_counter_id = 0;
				}
			}
			else if (value == Is.PLAYING)
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
        get { return _player.volume; }
        set { _player.volume = value; }
    }


    /**
    * @brief Plays the specified station.
    *
    * @param station The station to play.
    */
		public void play_station (Station station)
	{
		_player.stop ();
        _station = station;
        app().events.station_changed_sig (_station);
		_player.uri = (_station.urlResolved != null && _station.urlResolved != "") ? _station.urlResolved : _station.url;
		_play_error = false;
		Timeout.add (500, () =>
		// Wait a half of a second to play the station to help flush metadata
		{
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
            case Is.PLAYING:
            case Is.BUFFERING:
                _player.stop ();
                break;
            default:
                _play_error = false;
                _player.play ();
                break;
        }
    } // play_pause


    /**
     * @brief Stops the player
     *
     */
    public void stop () {
        _player.stop ();
    } //  stop


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
