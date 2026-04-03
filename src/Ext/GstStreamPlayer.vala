/**
 * SPDX-FileCopyrightText: Copyright © 2026 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file GstStreamPlayer.vala
 */

 using Gst;


namespace Tuner.Ext {

    public class GstStreamPlayer : GLib.Object, PlayerInterface {
        // Stream URL configured at construction time.
        public string stream_url { get; construct; }
        // App-level state derived from the GStreamer playbin state.
        private PlayerInterface.State _play_state = PlayerInterface.State.STOPPED;
        public PlayerInterface.State play_state { get { return _play_state; } }
        // Latest string metadata from the stream.
        private GLib.HashTable<string, string> _metadata;
        public GLib.HashTable<string, string> metadata { get { return _metadata; } }
        // Current output volume (0.0 - 1.0).
        private double _volume = 0.5;
        public double volume { get { return _volume; } }
        // Last observed RMS level in dB from the level element (more negative is quieter).
        public double last_rms_db { get; private set; default = -100.0; }
        // Optional per-stream trim in dB (positive/negative).
        public double trim_db { get; private set; default = 0.0; }

        private dynamic Element playbin;
        private dynamic Element level;

        public GstStreamPlayer (string stream_url) {
            // Create a per-stream playbin and attach a bus watcher.
            GLib.Object (stream_url: stream_url);
            _metadata = new GLib.HashTable<string, string> (GLib.str_hash, GLib.str_equal);
            playbin = ElementFactory.make ("playbin", "play");
            playbin.uri = stream_url;
            set_volume_level (0.5);
            setup_level_monitor ();

            Gst.Bus bus = playbin.get_bus ();
            bus.add_watch (0, bus_callback);
        }

        private bool bus_callback (Gst.Bus bus, Gst.Message message) {
            // Update state and metadata based on bus messages.
            switch (message.type) {
            case MessageType.ERROR:
                GLib.Error err;
                string debug;
                message.parse_error (out err, out debug);
                stdout.printf ("Error: %s\n", err.message);
                error_sig (err.message);
                set_play_state (PlayerInterface.State.STOPPED);
                break;
            case MessageType.EOS:
                stdout.printf ("end of stream\n");
                set_play_state (PlayerInterface.State.STOPPED);
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
                // Tags can include non-string values; only collect strings to avoid warnings.
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

        public void play () {
            // Transition playbin to PLAYING state.
            playbin.set_state (Gst.State.PLAYING);
            set_play_state (PlayerInterface.State.PLAYING);
        }

        public void stop () {
            // Reset playbin to NULL state and mark as stopped.
            playbin.set_state (Gst.State.NULL);
            set_play_state (PlayerInterface.State.STOPPED);
        }

        public void prepare () {
            // Pre-roll the pipeline without output.
            playbin.set_state (Gst.State.PAUSED);
            set_play_state (PlayerInterface.State.PAUSED);
        }

        public void set_volume_level (double volume) {
            // Clamp and apply volume to playbin.
            if (volume < 0.0) {
                volume = 0.0;
            } else if (volume > 1.0) {
                volume = 1.0;
            }
            _volume = volume;
            playbin.volume = apply_trim (volume);
        }

        public void set_trim_db_level (double trim_db) {
            // Apply a dB trim to balance perceived loudness across stations.
            this.trim_db = trim_db;
            playbin.volume = apply_trim (this.volume);
        }

        private double apply_trim (double volume) {
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

        private void setup_level_monitor () 
        {
            // Inject a level element so we can read RMS values for silence detection.
            level = ElementFactory.make ("level", "level");
            if (level != null) {
                level.set_property ("interval", (uint64) 100000000); // 100ms in ns
                level.set_property ("post-messages", true);
                playbin.set_property ("audio-filter", level);
            }
        }

        private void set_play_state (PlayerInterface.State state)
        {
            if (_play_state == state)
                return;
            _play_state = state;
            state_changed_sig (_play_state);
        } // set_play_state

        private void update_play_state (Gst.State state) 
        {
            set_play_state (map_play_state (state));
        } // update_play_state

        private PlayerInterface.State map_play_state (Gst.State state)
        {
            switch (state) {
            case Gst.State.PLAYING:
                return PlayerInterface.State.PLAYING;
            case Gst.State.PAUSED:
                return PlayerInterface.State.PAUSED;
            case Gst.State.READY:
                return PlayerInterface.State.BUFFERING;
            default:
                return PlayerInterface.State.STOPPED;
            }
        } // map_play_state
    } // GstStreamPlayer
} // namespace Tuner.Ext
