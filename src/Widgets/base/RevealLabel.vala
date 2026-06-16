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
    private bool _set_text_busy = false;    // Lock out concurrent updates
    private string _next_text;

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


    protected void clear() {
        _next_text = "";
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
     * Setting this text triggers the reveal animation.
     */
    public bool set_text ( string text ) 
    {
        // Prevent transition if same title is submitted multiple times
        if ( label_child.label == text) return true;      
        
        if (_set_text_busy)
        return false;

        _set_text_busy = true;

        reveal_child = false;
        _next_text = text;

        if ( label_child.label == "" && text != "") 
        // Reveal new text without fade if label is empty
        {
            label_child.label = _next_text;
            reveal_child = true;
              _set_text_busy = false;
            return true;
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
              _set_text_busy = false;
            return Source.REMOVE;
        }, Priority.DEFAULT_IDLE);    
        
        return true;
    } // set_text

}

