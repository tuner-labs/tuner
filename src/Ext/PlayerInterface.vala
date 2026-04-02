/**
 * SPDX-FileCopyrightText: Copyright © 2026 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file PlayerInterface.vala
 */

namespace Tuner.Ext {

    public interface PlayerInterface : GLib.Object {
        public enum State {
            BUFFERING,
            PAUSED,
            PLAYING,
            STOPPED,
            STOPPED_ERROR
        }

        public abstract StreamStatus status { get; }
        public abstract State play_state { get; }
        public abstract GLib.HashTable<string, string> metadata { get; }
        public abstract double volume { get; }

        public abstract void play ();
        public abstract void stop ();
        public abstract void set_volume_level (double volume);
    }

}
