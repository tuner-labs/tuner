/**
 * SPDX-FileCopyrightText: Copyright © 2026 <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file MetadataImagePopup.vala
 *
 */

using Gtk;
using Gdk;
using GLib;
using Tuner.Models;
using Tuner.Services;

/**
 * @brief Frameless popup window that shows metadata images.
 */
public class Tuner.Widgets.MetadataImagePopup : Gtk.Window
{
    private const int MAX_IMAGE_SIZE = 320;

    private Gtk.Image _image;
    private uint _load_generation = 0;
    private string _current_url = "";
    private bool _enabled = false;

    /**
     * @brief Create a frameless popup that shows metadata images.
     *
     * The popup attaches to the parent window, stays above it, and listens
     * for metadata changes to update the displayed image.
     *
     * @param parent Parent window to attach the popup to.
     */
    public MetadataImagePopup(Gtk.Window parent)
    {
        Object(
            type: Gtk.WindowType.TOPLEVEL,
            decorated: false,
            resizable: false,
            skip_taskbar_hint: true,
            skip_pager_hint: true
        );

        set_transient_for(parent);
        set_keep_above(true);
        set_type_hint(Gdk.WindowTypeHint.UTILITY);

        add_events(EventMask.BUTTON_PRESS_MASK);
        button_press_event.connect((event) =>
        {
            if (event.button == 1)
            {
                begin_move_drag((int)event.button, (int)event.x_root, (int)event.y_root, event.time);
                return true;
            }
            return false;
        });

        _image = new Gtk.Image();
        add(_image);

        hide();

        app().events.playback_metadata_changed_sig.connect((station, metadata) =>
        {
            handle_metadata(metadata);
        });
    } // MetadataImagePopup


    /**
     * @brief Enable or disable the popup.
     *
     * When disabled, the popup hides itself and ignores updates.
     *
     * @param enabled Whether the popup should be active.
     */
    public void set_enabled(bool enabled)
    {
        _enabled = enabled;
        if (!_enabled)
            hide();
    } // set_enabled


    /**
     * @brief Handle new metadata and trigger image loading.
     *
     * Hides the popup when disabled or when no valid image URL is found.
     *
     * @param metadata The latest metadata payload.
     */
    private void handle_metadata(StreamMetadata metadata)
    {
        if (!_enabled)
        {
            hide();
            return;
        } // if

        if (metadata == null || metadata.image == null)
        {
            hide();
            return;
        } // if

        var url = extract_image_url(metadata);
        if (url == "")
        {
            hide();
            return;
        } // if

        if (url == _current_url)
            return;

        _current_url = url;
        load_image_async.begin(url);
    } // handle_metadata


    /**
     * @brief Extract the best available image URL from metadata.
     *
     * @param metadata The metadata payload to inspect.
     * @return A URL string or an empty string if none found.
     */
    private string extract_image_url(StreamMetadata metadata)
    {
        return metadata.get_image_url();
    } // extract_image_url
    

    /**
     * @brief Load an image asynchronously and show it in the popup.
     *
     * Uses a generation counter to ignore stale responses and hides the popup
     * on failures or invalid responses.
     *
     * @param url Image URL to fetch.
     */
    private async void load_image_async(string url)
    {
        uint load_id = ++_load_generation;

        Uri? uri = null;
        try {
            uri = Uri.parse(url, UriFlags.NONE);
        } catch (UriError e) {
            hide();
            return;
        } // try

        uint status_code;
        InputStream? stream = yield HttpClient.GETasync(uri, Priority.LOW, out status_code);
        if (load_id != _load_generation)
            return;

        if (stream == null || status_code < 200 || status_code >= 300)
        {
            hide();
            return;
        } // if

        try {
            var pixbuf = yield new Gdk.Pixbuf.from_stream_at_scale_async(
                stream,
                MAX_IMAGE_SIZE,
                MAX_IMAGE_SIZE,
                true,
                null
            );
            if (load_id != _load_generation)
                return;
            _image.set_from_pixbuf(pixbuf);
            show_all();
        } catch (Error e) {
            hide();
        } // try
    } // load_image_async
} // MetadataImagePopup
