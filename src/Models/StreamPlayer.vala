/**
 * SPDX-FileCopyrightText: Copyright © 2026 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file StreamPlayer.vala
 */

namespace Tuner.Models{

    public interface StreamPlayer : GLib.Object 
    {
        public enum State 
        {
            BUFFERING,
            PAUSED,
            PLAYING,
            STOPPED,
            STOPPED_ERROR
        } // State

        public abstract State play_state { get; }
        public abstract GLib.HashTable<string, string> metadata { get; }
        public abstract double volume { get; }

        public signal void state_changed_sig (State state);
        public signal void metadata_changed_sig (GLib.HashTable<string, string> metadata);
        public signal void error_sig (string message);

        public abstract void play ();
        public abstract void stop ();
        public abstract void set_volume_level (double volume);

        /**
         * @brief Transition from the current stream to another stream.
         *
         * Implementations may crossfade when supported. If fading is not
         * available, implementations may fallback to an immediate stop of
         * the current stream and start of the next stream.
         *
         * @param next_player The next player instance to transition to.
         * @param target_volume Final volume for the next player (0.0 - 1.0).
         */
        public abstract void crossfade_to (StreamPlayer next_player, double target_volume);
    } // PlayerInterface

} // namespace
