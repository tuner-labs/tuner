/**
 * SPDX-FileCopyrightText: Copyright © 2020-2024 Louis Brauer <louis@brauer.family>
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later 
 *
 * @file RevealLabel.vala
 */

 using Gtk;
 using GLib;

/**
 * @class RevealLabel
 * @brief A custom widget that reveals a label with animation.
 *
 * This class extends Gtk.Revealer to create a label that can be revealed
 * and hidden with smooth transitions.
 * Uses Gtk.Label get_text and set_text for label text
 *
 * @extends Gtk.Revealer
 */
public class Tuner.Widgets.Base.RevealLabel : Gtk.Revealer 
{
    private bool _changing = false;            // A text change (fade out, clear, reveal) is under way
    private string _next_text = "";            // The text the change under way ends on
    private string? _pending_text = null;      // Text asked for during the change; the latest one wins

    /**
     * @brief Default duration for fade-in animation in milliseconds.
     */
    private const uint DEFAULT_FADE_DURATION = 1200u;

    /**
     * @property label_child
     * @brief The Gtk.Label widget contained within the revealer.
     */
    public Label label_child { get; construct set; }

    
    /** @property {string} label - Label text. Setting this property triggers the reveal animation. */
    public string label {
        get { return get_text(); }
        set { set_text ( value ); }
    } // label


    /**
     * @brief Initializes the RevealLabel with default properties.
     */
     construct {
        label_child = new Label ("");
        label_child.ellipsize = Pango.EllipsizeMode.MIDDLE;
        child = label_child;
        transition_type = RevealerTransitionType.CROSSFADE;
        transition_duration = DEFAULT_FADE_DURATION; 
    } // construct


    /**
     * @brief Clears the label text and any pending text.
     */
    protected void clear() {
        _next_text = "";
        _pending_text = null;
        label_child.label = "";
    } // clear


    /**
     * @brief The text displayed in the label.
     *
     */
    public unowned string get_text() {
            return label_child.label;
    } // get_text

    
    /**
     * @brief The text to display in the label.
     *
     * Setting this text triggers the reveal animation. Text set while a change is still under way is
     * not lost: the latest of it is shown as soon as that change is done.
     */
    public void set_text ( string text ) 
    {
        if ( _changing )
        // Keep only the latest text; it is shown when the change under way is done
        {
            _pending_text = ( text == _next_text ) ? null : text;
            return;
        }

        // Prevent transition if same title is submitted multiple times
        if ( label_child.label == text) return;

        start_change ( text );
    } // set_text


    /**
     * @brief Fades the label out, clears it, and reveals the new text.
     */
    private void start_change ( string text )
    {
        _changing = true;
        reveal_child = false;
        _next_text = text;

        if ( label_child.label == "" && text != "") 
        // Reveal new text without fade if label is empty
        {
            label_child.label = _next_text;
            reveal_child = true;
            finish_change ();
            return;
        }

        Timeout.add ( 11*DEFAULT_FADE_DURATION/10, () => 
        // Clear the text after fade has completed
        {
            label_child.label = "";
            return Source.REMOVE;
        },Priority.HIGH_IDLE);  

        Timeout.add (3*DEFAULT_FADE_DURATION/2, () => 
        // Update and reveal new text after fade and clear have completed
        {
            label_child.label = _next_text;
            reveal_child = true;
            finish_change ();
            return Source.REMOVE;
        }, Priority.DEFAULT_IDLE);    
    } // start_change


    /**
     * @brief The change is done: start on the text that was asked for meanwhile, if it differs from what is shown.
     */
    private void finish_change ()
    {
        _changing = false;

        var next = _pending_text;
        _pending_text = null;
        if ( next != null && next != label_child.label )
            start_change ( next );
    } // finish_change

}

