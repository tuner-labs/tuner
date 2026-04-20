/**
 * SPDX-FileCopyrightText: Copyright © 2020-2024 Louis Brauer <louis@brauer.family>
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file PlayingStationInfo.vala
 *
 * @brief PlayingStationInfo widget
 *
 */


using Gtk;
using Gdk;
using Tuner.Widgets.Base;
using Tuner.Controllers;
using Tuner.Models;

/**
 * @class Tuner.Widgets.PlayingStationInfo
 * @brief Displays station name, artwork and stream metadata for playing station.
 *
 * Provides a reveal-based transition when stations change and exposes
 * helper hooks for metadata updates and popover display.
 */
public class Tuner.Widgets.PlayingStationInfo : Revealer
{
    private const bool TRACE_METADATA_PATH = false;

    private const string DEFAULT_ICON_NAME = "tuner:internet-radio-symbolic";
    private const uint REVEAL_DELAY = 400u;
    private const uint STATION_CHANGE_SETTLE_DELAY_MS = 1200u;
    private const string PLACEHOLDER = _("Stream Metadata");
    private const int CONTENT_SPACING_PX = 10;
    private const int CONTENT_MARGIN_PX = 24;
    private const int ICON_FALLBACK_WIDTH_PX = 48;

    /** Station name label. */
    public Label station_label { get; private set; }
    /** Cycling label that displays the current track metadata. */
    public CyclingRevealLabel title_label { get; private set; }
    //public StationContextMenu menu { get; private set; }

    /** Favicon image for the current station. */
    public Image favicon_image = new Image.from_icon_name(DEFAULT_ICON_NAME, IconSize.DIALOG);

    /**
     * @brief Raw metadata string used by the popover and fallback display.
     */
    public string metadata {
        get { return _metadata_string; }
        internal set { _metadata_string = value; }
    } // metadata
    

    private string _metadata_string;
    private Station _station;
    private Gtk.Popover _metadata_popover;
    private Gtk.Label _metadata_label;
    private uint _hover_timeout_id = 0;
    private bool _popover_visible = false;
    private bool _transitioning = false;
    private Station? _pending_station = null;
    private StreamMetadata? _pending_metadata = null;
    private Gtk.Box _text_lane;

    /**
     * @brief Emitted after station transition visuals complete.
     */
    internal signal void info_changed_completed_sig();

    /**
     * @brief Creates a new PlayerInfo widget.
     *
     * @param window Parent window hosting the widget.
     * @param player Player controller.
     */
    public PlayingStationInfo(Window window, PlayerController player)
    {
        Object();

        transition_duration = REVEAL_DELAY;
        transition_type     = RevealerTransitionType.CROSSFADE;

        station_label = new Label("Tuner");
        station_label.get_style_context().add_class("station-label");
        station_label.ellipsize = Pango.EllipsizeMode.MIDDLE;
        station_label.halign = Align.CENTER;

        title_label = new CyclingRevealLabel(window, 100);
        title_label.get_style_context().add_class("track-info");
        title_label.halign = Align.CENTER;
        title_label.valign = Align.CENTER;
        title_label.hexpand = false;
        title_label.show_metadata = window.settings.stream_info;
        title_label.metadata_fast_cycle = window.settings.stream_info_fast;
        title_label.dynamic_shrink = window.settings.stream_info_dynamic_shrink;
        title_label.set_max_width_px (320);

        _text_lane = new Gtk.Box (Orientation.VERTICAL, 6);
        _text_lane.halign = Align.CENTER;
        _text_lane.hexpand = false;
        _text_lane.pack_start (station_label, false, false, 0);
        _text_lane.pack_start (title_label, false, false, 0);

        var content_row = new Gtk.Box (Orientation.HORIZONTAL, CONTENT_SPACING_PX);
        content_row.halign = Align.CENTER;
        content_row.valign = Align.CENTER;
        content_row.hexpand = false;
        content_row.pack_start (favicon_image, false, false, 0);
        content_row.pack_start (_text_lane, false, false, 0);

        var centered_lane = new Gtk.Box (Orientation.HORIZONTAL, 0);
        centered_lane.halign = Align.CENTER;
        centered_lane.valign = Align.CENTER;
        centered_lane.hexpand = true;
        centered_lane.pack_start (content_row, false, false, 0);

        add(centered_lane);
        reveal_child = false;

        size_allocate.connect ((allocation) =>
        {
            update_title_width_bound (allocation.width);
        });

        metadata = PLACEHOLDER;

        /*
		    Hook up title to metadata as a delayed popover.
		 */
        add_events(EventMask.ENTER_NOTIFY_MASK | EventMask.LEAVE_NOTIFY_MASK);
        enter_notify_event.connect((event) =>
        {
            if (_hover_timeout_id > 0 || _popover_visible)
                return false;
            _hover_timeout_id = Timeout.add(1000, () =>
            {
                _hover_timeout_id = 0;
                show_metadata_popover();
                return Source.REMOVE;
            });
            return false;
        });

        leave_notify_event.connect((event) =>
        {
            if (_hover_timeout_id > 0)
            {
                Source.remove(_hover_timeout_id);
                _hover_timeout_id = 0;
            }
            return false;
        });

        window.add_events(EventMask.BUTTON_PRESS_MASK);
        window.button_press_event.connect((event) =>
        {
            if (_popover_visible)
                hide_metadata_popover();
            return false;
        });

        app().events.playback_metadata_changed_sig.connect(handle_metadata_changed);
    } // constructor


    /**
     * @brief Bound metadata label width to current available widget width.
     */
    private void update_title_width_bound (int total_width)
    {
        int icon_width = favicon_image.get_allocated_width ();
        if (icon_width <= 0)
            icon_width = ICON_FALLBACK_WIDTH_PX;

        int max_title_width = total_width - icon_width - CONTENT_SPACING_PX - CONTENT_MARGIN_PX;
        if (max_title_width < 100)
            max_title_width = 100;

        title_label.set_max_width_px (max_title_width);
    } // update_title_width_bound


    /**
     * @brief Handles the display transition when a station changes.
     *
     * This clears the previous station display, waits a short settle interval,
     * and then reveals the new station with a crossfade.
     *
     * @param station The new station to display.
     */
    internal async void change_station(Station station)
    {
        hide_metadata_popover();
        reveal_child = false;
        queue_station_transition (station);

        Idle.add(() =>
        {
            Timeout.add(5 * REVEAL_DELAY / 3, () =>
            {
                favicon_image.clear();
                title_label.clear();
                station_label.label = "";
                _metadata_string = PLACEHOLDER;
                return Source.REMOVE;
            });

            Timeout.add(STATION_CHANGE_SETTLE_DELAY_MS, () =>
            {
                station.update_favicon_image.begin(
                    favicon_image,
                    true,
                    DEFAULT_ICON_NAME,
                    () =>
                    {
                        _station = station;
                        station_label.label = station.name;

                        reveal_child = true;
                        title_label.cycle();

                        _transitioning = false;
                        if (_pending_metadata != null)
                        {
                            apply_metadata(_pending_metadata);
                            _pending_metadata = null;
                            _pending_station = null;
                        }

                        info_changed_completed_sig();
                    }
                );

                return Source.REMOVE;
            });

            return Source.REMOVE;
        }, Priority.HIGH_IDLE);
    } // change_station


    /**
     * @brief Handles metadata updates from the player.
     *
     * Filters out updates that do not correspond to the active station.
     *
     * @param station Station that emitted the metadata.
     * @param metadata Metadata payload.
     */
    public void handle_metadata_changed(Station station, StreamMetadata metadata)
    {
        if (TRACE_METADATA_PATH)
        {
            stdout.printf (
                "[TRACE][PlayingStationInfo] received station=%s current=%s pending=%s transitioning=%s title='%s'\n",
                station.stationuuid,
                _station != null ? _station.stationuuid : "<null>",
                _pending_station != null ? _pending_station.stationuuid : "<null>",
                _transitioning ? "true" : "false",
                metadata.title
            );
        }

        if (_transitioning)
        {
            if (is_same_station(station, _pending_station))
            {
                if (TRACE_METADATA_PATH)
                    stdout.printf ("[TRACE][PlayingStationInfo] queued pending metadata for station=%s\n", station.stationuuid);
                _pending_metadata = metadata;
            }
            else if (TRACE_METADATA_PATH)
            {
                stdout.printf ("[TRACE][PlayingStationInfo] dropped during transition (station mismatch)\n");
            }
            return;
        }

        if (_station != null && !is_same_station(station, _station))
        {
            if (TRACE_METADATA_PATH)
                stdout.printf ("[TRACE][PlayingStationInfo] dropped (current station mismatch)\n");
            return;
        }

        if (_metadata_string == metadata.pretty_print)
        {
            if (TRACE_METADATA_PATH)
                stdout.printf ("[TRACE][PlayingStationInfo] dropped (unchanged pretty metadata)\n");
            return;
        }

        apply_metadata(metadata);
    } // handle_metadata_changed


    /**
     * @brief Mark a station transition as active so early metadata can be queued.
     *
     * Preserves already queued metadata for the same station.
     */
    internal void queue_station_transition (Station station)
    {
        _transitioning = true;
        if (!is_same_station (station, _pending_station))
        {
            _pending_station = station;
            _pending_metadata = null;
        }
    } // queue_station_transition


    /**
     * @brief Compares two stations by identity key.
     *
     * Uses station UUID to allow matching equivalent station instances.
     */
    private bool is_same_station(Station? left, Station? right)
    {
        if (left == null || right == null)
            return false;
        return left.stationuuid == right.stationuuid;
    } // is_same_station


    /**
     * @brief Applies a metadata payload to the UI.
     *
     * @param metadata Metadata payload.
     */
    private void apply_metadata(StreamMetadata metadata)
    {
        if (TRACE_METADATA_PATH)
        {
            stdout.printf (
                "[TRACE][PlayingStationInfo] apply title='%s' pretty_len=%u\n",
                metadata.title,
                metadata.pretty_print.length
            );
        }

        _metadata_string = metadata.pretty_print;
        title_label.notify_metadata_changed ();

        title_label.add_sublabel(1, metadata.genre, metadata.homepage);
        title_label.add_sublabel(2, metadata.audio_info);
        title_label.add_sublabel(3, metadata.org_loc);

        if (!title_label.set_text(metadata.title))
        {
            Timeout.add_seconds(3, () =>
            {
                title_label.set_text(metadata.title);
                return Source.REMOVE;
            });
        }

        if (_popover_visible)
            update_metadata_popover_text();
    } // apply_metadata


    /**
     * @brief Set whether the title label can shrink between metadata updates.
     */
    public void set_dynamic_shrink (bool enabled)
    {
        title_label.dynamic_shrink = enabled;
    } // set_dynamic_shrink


    /**
     * @brief Shows the metadata popover for the current station.
     */
    private void show_metadata_popover()
    {
        if (_station == null)
            return;

        if (_metadata_popover == null)
        {
            _metadata_popover = new Gtk.Popover(this);
            _metadata_popover.position = Gtk.PositionType.BOTTOM;
            _metadata_popover.set_border_width(8);
            _metadata_popover.get_style_context().add_class("metadata-popover");
            _metadata_popover.add_events(EventMask.BUTTON_PRESS_MASK);
            _metadata_popover.button_press_event.connect((event) =>
            {
                if (event.button == 3)
                {
                    copy_metadata_to_clipboard();
                    return true;
                }
                return false;
            });

            _metadata_label = new Gtk.Label("");
            _metadata_label.wrap = true;
            _metadata_label.max_width_chars = 48;
            _metadata_label.xalign = 0.0f;
            _metadata_label.get_style_context().add_class("metadata-label");
            _metadata_popover.add(_metadata_label);
            _metadata_popover.show_all();
            _metadata_popover.hide();
        }

        update_metadata_popover_text();
        _metadata_popover.show();
        _popover_visible = true;
    } // show_metadata_popover


    /**
     * @brief Hides the metadata popover if visible.
     */
    private void hide_metadata_popover()
    {
        if (_metadata_popover != null)
            _metadata_popover.hide();
        _popover_visible = false;
    } // hide_metadata_popover


    /**
     * @brief Returns the metadata blurb for the current station    
     */
    private string blurb()
    {
        if (_station == null)
            return "";
        
       StringBuilder sb = new StringBuilder();
       if (_station.starred)            
            sb.append("\u2605 ");
       sb.append(_station.name)
            .append("\n\n")
            .append(_station.popularity())
            .append("\n\n")
            .append(_station.locale())
            .append("\n\n");
       return sb.str;
    } // blurb


    /**
     * @brief Updates the metadata popover contents.
     */
    private void update_metadata_popover_text()
    {
        if (_metadata_label == null)
            return;
        
        string preamble = blurb();
        var text = _station != null ? @"$preamble$metadata" : PLACEHOLDER;
        _metadata_label.set_text(text);
    } // update_metadata_popover_text


    /**
     * @brief Copies the current metadata text to the clipboard.
     */
    private void copy_metadata_to_clipboard()
    {
        string preamble = blurb();
        var text = _station != null ? @"$preamble$metadata" : PLACEHOLDER;
        var clipboard = Gtk.Clipboard.get_default(Gdk.Display.get_default());
        if (clipboard != null)
        {
            clipboard.set_text(text, -1);
            show_copy_confirmation();
        }
    } // copy_metadata_to_clipboard


    /**
     * @brief Shows a short "Copied to clipboard" confirmation.
     */
    private void show_copy_confirmation()
    {
        if (_metadata_popover == null)
            return;

        var original_text = _metadata_label != null ? _metadata_label.get_text() : "";
        _metadata_label.set_text(_("Copied to clipboard"));
        _metadata_popover.show();
        _popover_visible = true;

        Timeout.add(1200, () =>
        {
            _metadata_label.set_text(original_text);
            if (!_popover_visible)
                _metadata_popover.hide();
            return Source.REMOVE;
        });
    } // show_copy_confirmation
} // PlayerInfo
