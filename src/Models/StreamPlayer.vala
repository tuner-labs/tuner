/**
 * SPDX-FileCopyrightText: Copyright © 2026 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file StreamPlayer.vala
 */

using Tuner.Events;

namespace Tuner.Models
{
    /**
     * @class StreamPlayer
     *
     * @brief StreamPlayer is an abstract class and interface to functions implemented by backend libraries
     *
     * This abstract class handles the player state, volume control, and stream metadata.
     * The actual playback logic and metadata extractionis delegated to backend-specific implementations.
     *
     * {@code StreamPlayer} reperesents one stream Url and is not reused.
     *
     */
    public abstract class StreamPlayer : GLib.Object
    {
        private const bool TRACE_METADATA_PATH = false;

        /** @brief Callback invoked when one-shot file playback ends. */
        public delegate void FilePlaybackFinished ();

        /**
         * @enum State
         *
         * @brief Represents the state of the stream player.
         *
         */
        public enum State 
        {
            BUFFERING,
            PAUSED,
            PLAYING,
            STOPPED,
            STOPPED_ERROR
        } // State

        // Per StreamPlayer signals


		internal signal void play_state_changed_sig (StreamPlayer.State state);	

        /** Signal emitted when a playback error occurs. */
        internal signal void playback_error_sig (string message);

		//public signal void player_state_changed_sig (StreamPlayer.State state);
        internal signal void stream_metadata_changed_sig ();



        /** @brief Stream URL configured at construction time. */
        public string stream_url { get; construct; }

        /** @brief App-level state derived from the GStreamer pipeline. */
        public State play_state { get; private set; default = State.STOPPED;}

        /** @brief Latest string metadata from the stream. */
        protected GLib.HashTable<string, string> _metadata; 
        //public GLib.HashTable<string, string> metadata { get { return _metadata; } }

        public StreamMetadata stream_metadata { get; construct; }

        /** @brief Current output volume (0.0 - 1.0). */
        public double volume { get; private set; default = 0.5; }


        /*
            Abstract methods to be implemented by backends. 
        */
        public abstract bool play_impl();
        public abstract bool stop_impl();
        public abstract bool crossfade_impl(StreamPlayer next_player, double target_volume);
        public abstract void set_volume_level_impl (double volume);


        /**
         * @brief Play a single file URI using the active backend implementation.
         *
         * @param file_uri URI to play (for example resource:///...).
         * @param volume Playback volume between 0.0 and 1.0.
         * @param on_finished Optional completion callback.
         * @return Backend playback handle, or null when setup failed.
         */
        public static GLib.Object? play_file (string file_uri, double volume, owned FilePlaybackFinished? on_finished = null)
        {
            return Tuner.play_stream_file (file_uri, volume, (owned) on_finished); // FIXME
        } // play_file


        /**
         * @brief Create a GStreamer-backed stream player.
         *
         * @param stream_url Stream URL for the playbin pipeline.
         */
        protected StreamPlayer (string stream_url)
        {
            GLib.Object (stream_url: stream_url) ;
            _metadata =  new GLib.HashTable<string, string> (GLib.str_hash, GLib.str_equal);
            _stream_metadata = new StreamMetadata ();
        } // constructor


        /** @brief Start playback. */
        public void play ()
        {
            if (!play_impl()) {
                update_play_state (State.STOPPED_ERROR);
                playback_error_sig ( "Failed to start playback.");
                return;
            }
            update_play_state (State.PLAYING);
        } // play

        /** @brief Stop playback */
        public void stop ()
        {
            if (!stop_impl()) {
                update_play_state (State.STOPPED_ERROR);
                playback_error_sig ( "Failed to start playback.");
                return;
            }
            update_play_state (State.STOPPED);
        } // stop


        /**
         * @brief Crossfade to the next player from this one
         *
         * @param next_player The next player instance to transition to.
         * @param target_volume Final volume for the next player (0.0 - 1.0).
         */
        public void crossfade_to (StreamPlayer next_player, double target_volume)
        {
            if (next_player == null)
            {
                stop ();
                next_player.set_volume_level (target_volume);
                next_player.play ();
                return;
            }

            crossfade_impl (next_player, target_volume);
        } // crossfade_to

        /**
         * @brief Set the output volume level.
         *
         * @param volume Volume between 0.0 and 1.0.
         */
        public void set_volume_level (double volume)
        {
            if (volume < 0.0) {
                volume = 0.0;
            } else if (volume > 1.0) {
                volume = 1.0;
            }
            _volume = volume;
            set_volume_level_impl (volume);
        } // set_volume_level



        //
        // Methods for implementing classes 
        //

        /**
         * @brief Update and emit the app-level play state.
         *
         * This method is used by the backend-specific implementations to reflect changes 
         * in the actual playback state in the app-level state and emit the corresponding signal.
         *
         * @param state New app-level state.
         */
        protected void update_play_state (StreamPlayer.State state)
        {
            if (_play_state == state)
                return;
            _play_state = state;
            play_state_changed_sig ( _play_state);
            //  AppEventBus.player_state_changed_sig (this, _play_state);
        } // update_play_state


        /**
         * @brief Emit the playback error signal.
         *
         * @param message Error message.
         */
        protected void playback_error (string message)
        {
            playback_error_sig ( message);
        } // playback_error


        /**
         * @brief Emit the stream metadata changed signal.
         */
        protected void metadata_changed()
        {
            bool changed = stream_metadata.process_tag_table (_metadata);
            if (TRACE_METADATA_PATH)
            {
                stdout.printf (
                    "[TRACE][StreamPlayer] metadata_changed stream=%s changed=%s title='%s' pretty_len=%u\n",
                    stream_url,
                    changed ? "true" : "false",
                    stream_metadata.title,
                    stream_metadata.pretty_print.length
                );
            }

            if (!changed)
                return;

            stream_metadata_changed_sig ();
        } // metadata_changed
    } // Tuner.Models.StreamPlayer
} // namespace Tuner.Models
