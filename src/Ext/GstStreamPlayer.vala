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
    public class GstStreamPlayer :  StreamPlayer
    {
        private const bool TRACE_METADATA_PATH = false;

        private static GstFader? shared_fader;
        private static uint default_fade_duration_ms = 1500;
        private static uint default_fade_interval_ms = 50;
        private static GstFader.FadeCurve default_fade_curve = GstFader.FadeCurve.LINEAR;


        /** @brief Last observed RMS level in dB from the level element. */
        public double last_rms_db { get; private set; default = -100.0; }

        /** @brief Optional per-stream trim in dB (positive/negative). */
        public double trim_db { get; private set; default = 0.0; }

        private dynamic Element playbin;
        private dynamic Element level;


        /**
         * @brief Create a GStreamer-backed stream player.
         *
         * @param stream_url Stream URL for the playbin pipeline.
         */
        public GstStreamPlayer (string stream_url)
        {
            base ( stream_url);
            
            playbin = ElementFactory.make ("playbin", "play");
            //playbin.user_agent = Tuner.user_agent ();
            playbin.uri = stream_url;

            set_volume_level (0.5);
            setup_level_monitor ();
            Gst.Bus bus = playbin.get_bus ();
            bus.add_watch (0, bus_callback);
        } // constructor


        /**
         * @brief Play a single file URI with the GStreamer backend.
         *
         * @param file_uri URI to play.
         * @param volume Playback volume between 0.0 and 1.0.
         * @param on_finished Optional completion callback.
         * @return Active playback handle, or null when setup failed.
         */
        public static GLib.Object? play_file_backend (string file_uri, double volume, owned StreamPlayer.FilePlaybackFinished? on_finished = null)
        {
            var startup_playbin = Gst.ElementFactory.make ("playbin", "stream-player-file");
            if (startup_playbin == null)
                return null;

            startup_playbin.set ("uri", file_uri);
            startup_playbin.set ("volume", volume);

            var bus = startup_playbin.get_bus ();
            if (bus != null)
            {
                bus.add_signal_watch ();
                bus.message.connect ((message) => {
                    switch (message.type)
                    {
                        case Gst.MessageType.EOS:
                        case Gst.MessageType.ERROR:
                            startup_playbin.set_state (Gst.State.NULL);
                            bus.remove_signal_watch ();
                            if (on_finished != null)
                                on_finished ();
                            break;
                        default:
                            break;
                    } // switch
                });
            }

            startup_playbin.set_state (Gst.State.PLAYING);
            return startup_playbin;
        } // play_file_backend

                /** @brief Start playback. */
        public override bool play_impl ()
        {
            playbin.set_state (Gst.State.PLAYING);
            return true;
        } // play
        

        /** @brief Stop playback and reset the pipeline. */
        public override bool stop_impl ()
        {
            playbin.set_state (Gst.State.NULL);
            return true;
        } // stop


        /**
         * @brief Set the output volume level.
         *
         * @param volume Volume between 0.0 and 1.0.
         */
        public override void set_volume_level_impl (double volume)
        {
            playbin.volume = apply_trim (volume);
        } // set_volume_level


        /**
         * @brief Crossfade from this stream to the next stream.
         *
         * @param next_player The next player instance to transition to.
         * @param target_volume Final volume for the next player (0.0 - 1.0).
         */
        public override bool crossfade_impl (StreamPlayer next_player, double target_volume)
        {
            var next_gst = next_player as GstStreamPlayer;
            if (next_gst == null)
            {
                stop ();
                next_player.set_volume_level (target_volume);
                next_player.play ();
                return true;
            }

            var fader = get_fader ();
            fader.crossfade (this, next_gst, target_volume, default_fade_duration_ms, default_fade_interval_ms);
            return true;
        } // crossfade


        // ----------------------------------------------------------------



        /**
         * @brief Handle GStreamer bus messages.
         *
         * @param bus GStreamer bus instance.
         * @param message Bus message to process.
         * @return True to keep the watch active.
         */
        private bool bus_callback (Gst.Bus bus, Gst.Message message)
        {
            switch (message.type) 
            {
            case MessageType.ERROR:
                GLib.Error err;
                string debug;
                message.parse_error (out err, out debug);
                //  stdout.printf ("Error: %s\n", err.message);
                playback_error (err.message);
                update_play_state (State.STOPPED_ERROR);
                break;

            case MessageType.EOS:
                // stdout.printf ("end of stream\n");
                update_play_state (State.STOPPED);
                break;

            case MessageType.STATE_CHANGED:
                Gst.State oldstate;
                Gst.State newstate;
                Gst.State pending;
                message.parse_state_changed (out oldstate, out newstate, out pending);
                update_play_state (map_play_state(newstate));
                break;

            case MessageType.TAG:
                //stdout.printf ("taglist found\n");
                Gst.TagList? tag_list = null;
                message.parse_tag (out tag_list);
                if (tag_list != null) {
                    bool changed = false;
                    var count = tag_list.n_tags ();
                    for (uint i = 0; i < count; i++) 
                    {
                        var tag = tag_list.nth_tag_name (i);
                        unowned GLib.Value? value = tag_list.get_value_index (tag, 0);
                        if (value != null && value.holds (typeof (string))) {
                            var tag_string = value.get_string ();
                            _metadata.insert (tag, tag_string);
                            changed = true;
                        }
                    }
                    if (TRACE_METADATA_PATH)
                    {
                        string? title = _metadata.lookup ("title");
                        stdout.printf (
                            "[TRACE][GstStreamPlayer] TAG stream=%s tags=%u title='%s' changed=%s\n",
                            stream_url,
                            count,
                            title != null ? title : "",
                            changed ? "true" : "false"
                        );
                    }
                    if (changed)
                        metadata_changed();
                }
                break;

            case MessageType.ELEMENT:
                unowned Gst.Structure? structure = message.get_structure ();
                if (structure != null && structure.has_name ("level")) 
                {
                    unowned GLib.Value? list_value = structure.get_value ("rms");
                    if (list_value != null) 
                    {
                        if (list_value.holds (typeof (Gst.ValueList))) 
                        {
                            uint size = Gst.ValueList.get_size (list_value);
                            if (size > 0) 
                            {
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
                } // if
                break;
                
            default:
                break;
            } // switch

            return true;
        } // bus_callback


        /**
         * @brief Update default crossfade settings for all players.
         *
         * These defaults are used by `crossfade_to` unless overridden later.
         */
        //  public static void set_crossfade_defaults (uint duration_ms, uint interval_ms = 50, GstFader.FadeCurve curve = GstFader.FadeCurve.LINEAR)
        //  {
        //      default_fade_duration_ms = duration_ms;
        //      default_fade_interval_ms = interval_ms;
        //      default_fade_curve = curve;
        //      if (shared_fader != null)
        //          apply_fade_defaults (shared_fader);
        //  } // set_crossfade_defaults


        /** 
         * @brief Pre-roll the pipeline without output. 
         */
        internal void prepare ()
        {
            playbin.set_state (Gst.State.PAUSED);
            update_play_state (State.PAUSED);
        } // prepare


        /**
         * @brief Set a per-stream trim in dB.
         *
         * @param trim_db Trim value in dB.
         */
        internal void set_trim_db_level (double trim_db)
        {
            this.trim_db = trim_db;
            playbin.volume = apply_trim (this.volume);
        } // set_trim_db_level


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
        } // apply_trim


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
        } // setup_level_monitor


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
                return State.PLAYING;
            case Gst.State.PAUSED:
                return State.PAUSED;
            case Gst.State.READY:
                return State.BUFFERING;
            default:
                return State.STOPPED;
            }
        } // map_play_state
    } // GstStreamPlayer
} // namespace Tuner.Ext
