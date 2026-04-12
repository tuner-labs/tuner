/**
 * SPDX-FileCopyrightText: Copyright © 2026 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file GstStreamPlayer.vala
 */

using Gst;
using Tuner.Models;

namespace Tuner.Ext
{
    /**
     * @class GstStreamPlayer
     * @brief GStreamer-backed stream implementation for `PlayerInterface`.
     *
     * Wraps a `playbin` pipeline, translates GStreamer state into the app-level
     * state enum, and emits metadata and error signals.
     */
    public class GstStreamPlayer : GLib.Object, StreamPlayer
    {
        private static GstFader? shared_fader;
        private static uint default_fade_duration_ms = 1500;
        private static uint default_fade_interval_ms = 50;
        private static GstFader.FadeCurve default_fade_curve = GstFader.FadeCurve.LINEAR;

        /** @brief Stream URL configured at construction time. */
        public string stream_url { get; construct; }

        /** @brief App-level state derived from the GStreamer pipeline. */
        private StreamPlayer.State _play_state = StreamPlayer.State.STOPPED;
        public StreamPlayer.State play_state { get { return _play_state; } }

        /** @brief Latest string metadata from the stream. */
        private GLib.HashTable<string, string> _metadata;
        public GLib.HashTable<string, string> metadata { get { return _metadata; } }

        /** @brief Current output volume (0.0 - 1.0). */
        private double _volume = 0.5;
        public double volume { get { return _volume; } }

        /** @brief Last observed RMS level in dB from the level element. */
        public double last_rms_db { get; private set; default = -100.0; }

        /** @brief Optional per-stream trim in dB (positive/negative). */
        public double trim_db { get; private set; default = 0.0; }

        private dynamic Element playbin;
        private dynamic Element level;

        /**
         * @brief Update default crossfade settings for all players.
         *
         * These defaults are used by `crossfade_to` unless overridden later.
         */
        public static void set_crossfade_defaults (uint duration_ms, uint interval_ms = 50, GstFader.FadeCurve curve = GstFader.FadeCurve.LINEAR)
        {
            default_fade_duration_ms = duration_ms;
            default_fade_interval_ms = interval_ms;
            default_fade_curve = curve;
            if (shared_fader != null)
                apply_fade_defaults (shared_fader);
        } // set_crossfade_defaults

        /**
         * @brief Create a GStreamer-backed stream player.
         *
         * @param stream_url Stream URL for the playbin pipeline.
         */
        public GstStreamPlayer (string stream_url)
        {
            GLib.Object (stream_url: stream_url);
            _metadata = new GLib.HashTable<string, string> (GLib.str_hash, GLib.str_equal);
            playbin = ElementFactory.make ("playbin", "play");
            playbin.uri = stream_url;
            set_volume_level (0.5);
            setup_level_monitor ();
            playbin.user_agent = Tuner.user_agent ();

            Gst.Bus bus = playbin.get_bus ();
            bus.add_watch (0, bus_callback);
        }

        /**
         * @brief Handle GStreamer bus messages.
         *
         * @param bus GStreamer bus instance.
         * @param message Bus message to process.
         * @return True to keep the watch active.
         */
        private bool bus_callback (Gst.Bus bus, Gst.Message message)
        {
            switch (message.type) {
            case MessageType.ERROR:
                GLib.Error err;
                string debug;
                message.parse_error (out err, out debug);
                stdout.printf ("Error: %s\n", err.message);
                error_sig (err.message);
                set_play_state (StreamPlayer.State.STOPPED);
                break;
            case MessageType.EOS:
                stdout.printf ("end of stream\n");
                set_play_state (StreamPlayer.State.STOPPED);
                break;
            case MessageType.STATE_CHANGED:
                Gst.State oldstate;
                Gst.State newstate;
                Gst.State pending;
                message.parse_state_changed (out oldstate, out newstate, out pending);
                update_play_state (newstate);
                stdout.printf ("state changed: %s->%s:%s\n",
                            oldstate.to_string (), newstate.to_string (),
                            pending.to_string ());
                break;
            case MessageType.TAG:
                stdout.printf ("taglist found\n");
                Gst.TagList? tag_list = null;
                message.parse_tag (out tag_list);
                if (tag_list != null) {
                    bool changed = false;
                    var count = tag_list.n_tags ();
                    for (uint i = 0; i < count; i++) {
                        var tag = tag_list.nth_tag_name (i);
                        unowned GLib.Value? value = tag_list.get_value_index (tag, 0);
                        if (value != null && value.holds (typeof (string))) {
                            var tag_string = value.get_string ();
                            _metadata.insert (tag, tag_string);
                            changed = true;
                            stdout.printf ("tag: %s = %s\n", tag, tag_string);
                        }
                    }
                    if (changed)
                        metadata_changed_sig (_metadata);
                }
                break;
            case MessageType.ELEMENT:
                unowned Gst.Structure? structure = message.get_structure ();
                if (structure != null && structure.has_name ("level")) {
                    unowned GLib.Value? list_value = structure.get_value ("rms");
                    if (list_value != null) {
                        if (list_value.holds (typeof (Gst.ValueList))) {
                            uint size = Gst.ValueList.get_size (list_value);
                            if (size > 0) {
                                unowned GLib.Value? value = Gst.ValueList.get_value (list_value, 0);
                                if (value != null) {
                                    if (value.holds (typeof (double))) {
                                        last_rms_db = value.get_double ();
                                    } else if (value.holds (typeof (float))) {
                                        last_rms_db = (double) value.get_float ();
                                    }
                                }
                            }
                        } else if (list_value.holds (typeof (double))) {
                            last_rms_db = list_value.get_double ();
                        } else if (list_value.holds (typeof (float))) {
                            last_rms_db = (double) list_value.get_float ();
                        }
                    }
                }
                break;
            default:
                break;
            }

            return true;
        }

        /** @brief Start playback. */
        public void play ()
        {
            playbin.set_state (Gst.State.PLAYING);
            set_play_state (StreamPlayer.State.PLAYING);
        }

        /** @brief Stop playback and reset the pipeline. */
        public void stop ()
        {
            playbin.set_state (Gst.State.NULL);
            set_play_state (StreamPlayer.State.STOPPED);
        }

        /**
         * @brief Crossfade from this stream to the next stream.
         *
         * @param next_player The next player instance to transition to.
         * @param target_volume Final volume for the next player (0.0 - 1.0).
         */
        public void crossfade_to (StreamPlayer next_player, double target_volume)
        {
            var next_gst = next_player as GstStreamPlayer;
            if (next_gst == null)
            {
                stop ();
                next_player.set_volume_level (target_volume);
                next_player.play ();
                return;
            }

            var fader = get_fader ();
            fader.crossfade (this, next_gst, target_volume, default_fade_duration_ms, default_fade_interval_ms);
        }

        /** @brief Pre-roll the pipeline without output. */
        public void prepare ()
        {
            playbin.set_state (Gst.State.PAUSED);
            set_play_state (StreamPlayer.State.PAUSED);
        }

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
            playbin.volume = apply_trim (volume);
        }

        /**
         * @brief Set a per-stream trim in dB.
         *
         * @param trim_db Trim value in dB.
         */
        public void set_trim_db_level (double trim_db)
        {
            this.trim_db = trim_db;
            playbin.volume = apply_trim (this.volume);
        }

        /**
         * @brief Apply trim to the volume and clamp to [0.0, 1.0].
         *
         * @param volume Base volume.
         * @return Adjusted volume.
         */
        private double apply_trim (double volume)
        {
            if (trim_db == 0.0) {
                return volume;
            }
            double multiplier = Math.pow (10.0, trim_db / 20.0);
            double adjusted = volume * multiplier;
            if (adjusted < 0.0) {
                return 0.0;
            }
            if (adjusted > 1.0) {
                return 1.0;
            }
            return adjusted;
        }

        private static GstFader get_fader ()
        {
            if (shared_fader == null)
            {
                shared_fader = new GstFader ();
                apply_fade_defaults (shared_fader);
            }
            return shared_fader;
        } // get_fader

        private static void apply_fade_defaults (GstFader fader)
        {
            fader.set_duration_ms (default_fade_duration_ms);
            fader.set_curve (default_fade_curve);
        } // apply_fade_defaults

        /**
         * @brief Configure RMS monitoring via the `level` element.
         */
        private void setup_level_monitor ()
        {
            level = ElementFactory.make ("level", "level");
            if (level != null) {
                level.set_property ("interval", (uint64) 100000000); // 100ms in ns
                level.set_property ("post-messages", true);
                playbin.set_property ("audio-filter", level);
            }
        }

        /**
         * @brief Update and emit the app-level play state.
         *
         * @param state New app-level state.
         */
        private void set_play_state (StreamPlayer.State state)
        {
            if (_play_state == state)
                return;
            _play_state = state;
            state_changed_sig (_play_state);
        } // set_play_state

        /**
         * @brief Map GStreamer states into app-level state and emit updates.
         *
         * @param state GStreamer state.
         */
        private void update_play_state (Gst.State state)
        {
            set_play_state (map_play_state (state));
        } // update_play_state

        /**
         * @brief Translate GStreamer state into `PlayerInterface.State`.
         *
         * @param state GStreamer state.
         * @return App-level state.
         */
        private StreamPlayer.State map_play_state (Gst.State state)
        {
            switch (state) {
            case Gst.State.PLAYING:
                return StreamPlayer.State.PLAYING;
            case Gst.State.PAUSED:
                return StreamPlayer.State.PAUSED;
            case Gst.State.READY:
                return StreamPlayer.State.BUFFERING;
            default:
                return StreamPlayer.State.STOPPED;
            }
        } // map_play_state
    } // GstStreamPlayer
} // namespace Tuner.Ext
