/**
 * SPDX-FileCopyrightText: Copyright © 2020-2024 Louis Brauer <louis@brauer.family>
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file PlayerInfo.vala
 *
 * @brief PlayerInfo widget
 *
 */


using Gtk;
using Gdk;
using Tuner.Widgets.Base;
using Tuner.Controllers;
using Tuner.Models;

/**
 * @class Tuner.Widgets.PlayerInfo
 * @brief Displays station name, artwork, and stream metadata.
 *
 * Provides a reveal-based transition when stations change and exposes
 * helper hooks for metadata updates and popover display.
 */
public class Tuner.Widgets.PlayerInfo : Revealer
{
    private const string DEFAULT_ICON_NAME = "tuner:internet-radio-symbolic";
    private const uint REVEAL_DELAY = 400u;
    private const uint STATION_CHANGE_SETTLE_DELAY_MS = 1200u;
    private const string STREAM_METADATA = _("Stream Metadata");

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
        get { return _metadata; }
        internal set { _metadata = value; }
    }

    private string _metadata;
    private Station _station;
    private uint grid_min_width = 0;
    private Gtk.Popover _metadata_popover;
    private Gtk.Label _metadata_label;
    private uint _hover_timeout_id = 0;
    private bool _popover_visible = false;
    private bool _transitioning = false;
    private Station? _pending_station = null;
    private Metadata? _pending_metadata = null;

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
    public PlayerInfo(Window window, PlayerController player)
    {
        Object();

        transition_duration = REVEAL_DELAY;
        transition_type     = RevealerTransitionType.CROSSFADE;

        station_label = new Label("Tuner");
        station_label.get_style_context().add_class("station-label");
        station_label.ellipsize = Pango.EllipsizeMode.MIDDLE;

        title_label = new CyclingRevealLabel(window, 100);
        title_label.get_style_context().add_class("track-info");
        title_label.halign = Align.CENTER;
        title_label.valign = Align.CENTER;
        title_label.show_metadata = window.settings.stream_info;
        title_label.metadata_fast_cycle = window.settings.stream_info_fast;

        var station_grid = new Grid();
        station_grid.column_spacing = 10;
        station_grid.set_halign(Align.FILL);
        station_grid.set_valign(Align.CENTER);

        station_grid.attach(favicon_image, 0, 0, 1, 2);
        station_grid.attach(station_label, 1, 0, 1, 1);
        station_grid.attach(title_label, 1, 1, 1, 1);

        station_grid.size_allocate.connect((allocate) =>
        {
            if (grid_min_width == 0)
                grid_min_width = allocate.width;
        });

        add(station_grid);
        reveal_child = false;

        metadata = STREAM_METADATA;

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

        app().events.metadata_changed_sig.connect(handle_metadata_changed);
    }

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
        _transitioning = true;
        _pending_station = station;
        _pending_metadata = null;

        Idle.add(() =>
        {
            Timeout.add(5 * REVEAL_DELAY / 3, () =>
            {
                favicon_image.clear();
                title_label.clear();
                station_label.label = "";
                _metadata = STREAM_METADATA;
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
    public void handle_metadata_changed(Station station, Metadata metadata)
    {
        if (_transitioning)
        {
            if (_pending_station != null && station == _pending_station)
                _pending_metadata = metadata;
            return;
        }

        if (_station != null && station != _station)
            return;

        if (_metadata == metadata.pretty_print)
            return;

        apply_metadata(metadata);
    }

    /**
     * @brief Applies a metadata payload to the UI.
     *
     * @param metadata Metadata payload.
     */
    private void apply_metadata(Metadata metadata)
    {
        _metadata = metadata.pretty_print;

        if (_metadata == "")
        {
            _metadata = STREAM_METADATA;
            return;
        }

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
    }


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
    }

    /**
     * @brief Hides the metadata popover if visible.
     */
    private void hide_metadata_popover()
    {
        if (_metadata_popover != null)
            _metadata_popover.hide();
        _popover_visible = false;
    }

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
    }

    /**
     * @brief Updates the metadata popover contents.
     */
    private void update_metadata_popover_text()
    {
        if (_metadata_label == null)
            return;
        
        string preamble = blurb();
        var text = _station != null ? @"$preamble$(metadata)" : STREAM_METADATA;
        _metadata_label.set_text(text);
    }

    /**
     * @brief Copies the current metadata text to the clipboard.
     */
    private void copy_metadata_to_clipboard()
    {
        string preamble = blurb();
        var text = _station != null ? @"$preamble$(metadata)" : STREAM_METADATA;
        var clipboard = Gtk.Clipboard.get_default(Gdk.Display.get_default());
        if (clipboard != null)
        {
            clipboard.set_text(text, -1);
            show_copy_confirmation();
        }
    }

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
    }
} 
