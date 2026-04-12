/**
 * SPDX-FileCopyrightText: Copyright © 2026 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file PlayerInterface.vala
 */

namespace Tuner.Models{

    public interface Player : GLib.Object 
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
    } // PlayerInterface

} // namespace
