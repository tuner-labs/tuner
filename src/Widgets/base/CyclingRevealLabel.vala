/**
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file CyclingRevealLabel.vala
 */

 using Gee;
 using Gtk;
 using GLib;

 
 /**
 * @class CyclingRevealLabel
 * @brief A custom widget that reveals a cycling label with animation.
 *
 * This class extends Tuner.RevealLabel to add cycling through of label text
 * and with damping between the different labels so grids do not bounce too much
 *
 * @extends Tuner.RevealLabel
 */
public class Tuner.Widgets.Base.CyclingRevealLabel : RevealLabel {

    private const int SUBTITLE_MIN_DISPLAY_SECONDS = 3;
    private const int WIDTH_PADDING_PX = 24;
    private const uint WIDTH_ANIMATION_INTERVAL_MS = 16;
    private const int DEFAULT_MAX_LABEL_WIDTH = 420;
    private const uint WIDTH_ANIMATION_MIN_MS = 120;
    private const uint WIDTH_ANIMATION_MAX_MS = 360;

    public bool show_metadata { get; set; }

    public bool metadata_fast_cycle { 
        get { return _metadata_fast_cycle; } 
        set {        
            if ( _metadata_fast_cycle == value ) return;
            if (value)
            // slow>fast
            {
                _metadata_fast_cycle = true;
                _cycle_phases = _cycle_phases_fast;
            }
            else
            // fast>slow
            {
                _metadata_fast_cycle = false;
                _cycle_phases = _cycle_phases_slow;
            } //else
        } // set
     } // metadata_fast_cycle 

    public bool dynamic_shrink {
        get { return _dynamic_shrink; }
        set { _dynamic_shrink = value; }
    } // dynamic_shrink

    private bool _metadata_fast_cycle;
    private bool _dynamic_shrink = false;
    private bool _metadata_changed_since_last_set = true;

    private uint _label_cycle_id = 0;
    private uint _width_animation_id = 0;
    private int _min_count_down;
    private int _min_label_width;
    private int _current_width;
    private int _target_width;
    private int _max_label_width = DEFAULT_MAX_LABEL_WIDTH;
    private int _animation_start_width;
    private int _animation_end_width;
    private int64 _animation_start_us;
    private uint _animation_duration_ms;
    private uint16 _display_seconds = 0;   // Mix up the cycle phase start point
    private uint16[] _cycle_phases_fast = {5,11,17,19,23}; // Fast cycle times - primes so everyone gets a chance
    private uint16[] _cycle_phases_slow = {23,37,43,47,53}; // Title, plus four subtitles
    private uint16[] _cycle_phases;  

    private Gee.Map<uint, string> sublabels = new Gee.HashMap<uint, string>();


    public CyclingRevealLabel (Widget _follow, int min_label_width, string? str = null) 
    {
        Object();
        
        label_child.set_line_wrap(false);
        label_child.set_justify(Justification.CENTER);
        base.label_child.set_text( str); 
        // Width is animated by text content and bounded by parent width.
        hexpand = false;
        halign = Align.CENTER;

        _min_label_width = min_label_width;
        _current_width = min_label_width;
        _target_width = min_label_width;
        set_size_request (_min_label_width, -1);
        // Caller controls max width via `set_max_width_px`.

        _cycle_phases = _cycle_phases_fast;
    } // CyclingRevealLabel


    public new string label {
        get { return get_text(); }
        set { set_text ( value ); }
    }


    /**
     * @brief gets/Sets the label
     *
     */
    public new bool set_text( string text )
    {    
        if ( text == base.get_text() ) return true;

        debug(@"CL set text: $(base.get_text()) > $text");
        if ( base.set_text(text) )
        {
            int target_width = measure_target_width (text);
            if (!_dynamic_shrink
                && !_metadata_changed_since_last_set
                && target_width < _current_width)
            {
                target_width = _current_width;
            }
            animate_width_to (target_width);
            _metadata_changed_since_last_set = false;
            return true;
        }
        
        debug(@"CL set text - Failed: $text");
        return false;
     } // label


    /**
     * @brief Marks that a new metadata payload was applied.
     */
    public void notify_metadata_changed ()
    {
        _metadata_changed_since_last_set = true;
    } // notify_metadata_changed


    /**
     * @brief Set the hard maximum width for this label.
     *
     * Long text is ellipsized beyond this width.
     */
    public void set_max_width_px (int max_width)
    {
        if (max_width < _min_label_width)
            max_width = _min_label_width;
        if (_max_label_width == max_width)
            return;
        _max_label_width = max_width;
        animate_width_to (measure_target_width (base.get_text ()));
    } // set_max_width_px


    /**
     * @brief Adds a sublabel at the given position
     *
     */
     public void add_sublabel(int position, string? sublabel1, string? sublabel2 = null)
     {
         if ( position <= 0 || position >= _cycle_phases.length ) return;    // Main label not sublabel, or too deep
 
         if ( sublabel1 == null || sublabel1.strip().length == 0 ) 
         {
             sublabels.unset(position);
         }
         else
         {
            var text = (sublabel2 == null || sublabel2.strip() == "" ) ? sublabel1.strip() : sublabel1.strip()+" - "+sublabel2.strip() ;
            sublabels.set(position, text);
         }
     } // add_sublabel
 

    /**
     * @brief Adds a sublabel at the given position
     *
     */
    //   public void add_stacked_sublabel(int position, string? sublabel1, string? sublabel2 = null)
    //   {
    //       if ( position <= 0 || position >= cycle_phases.length ) return;    // Main label not sublabel, or too deep
 
    //       if ( sublabel1 == null || sublabel1.strip().length == 0 ) 
    //       {
    //           sublabels.unset(position);
    //       }
    //       else
    //       {
    //          sublabels.set(position, (sublabel2 == null || sublabel2.strip() == "" ) ? sublabel1.strip() : sublabel1.strip()+"\n"+sublabel2.strip() );
    //       }
    //   } // add_sublabel
 
  
    /**
     * @brief Stops cycling the labels
     *
     */
    public void stop()
    {
        if ( _label_cycle_id > 0 ) 
        {
            Source.remove(_label_cycle_id);
            _label_cycle_id = 0;
        }

        if ( _width_animation_id > 0 ) 
        {
            Source.remove(_width_animation_id);
            _width_animation_id = 0;
        }
    } // stop


    /**
     * @brief Clears the cycling of the subtitles
     *
     */
    public new void clear()
    {
        stop();
        base.clear();
        sublabels.clear();
        animate_width_to (_min_label_width);
    } // clear


    /**
     * @brief Cycles the labels
     *
     */
    public void cycle() 
    { 
        stop();

        uint last_position = 99;

        Idle.add (() => 
        // Initiate the fade out
        {
            _label_cycle_id = Timeout.add_seconds_full(Priority.LOW, 1, () => 
            // New label timer
            {
                _display_seconds++;

                if ( 0 < _min_count_down-- )
                {
                    return Source.CONTINUE;  
                }

                if ( ! child_revealed ) 
                {
                    reveal_child = true;
                    _min_count_down = SUBTITLE_MIN_DISPLAY_SECONDS;
                    return Source.CONTINUE;    // Still processing reveal
                }

                foreach ( var position in sublabels.keys)
                {
                    if ( !show_metadata && position != 0 ) break;   // Do not show sublabels

                    if ( ( _display_seconds % _cycle_phases[position] == 0 ) 
                        && position != last_position
                        //  && sublabels.get(position) != "" 
                    ) 
                    {
                        set_text(sublabels.get(position));
                        last_position = position;
                    }
                }
                return Source.CONTINUE; // Leave timer to be recalled
            });

            return Source.REMOVE;
        });  
    } // cycle


    private int measure_target_width (string text)
    {
        int max_width = _max_label_width;

        if (text == null || text.strip ().length == 0)
            return _min_label_width;

        var layout = label_child.create_pango_layout (text);
        int text_width = 0;
        int text_height = 0;
        layout.get_pixel_size (out text_width, out text_height);

        int desired_width = text_width + WIDTH_PADDING_PX;
        if (desired_width < _min_label_width)
            desired_width = _min_label_width;
        if (desired_width > max_width)
            desired_width = max_width;

        return desired_width;
    } // measure_target_width


    private void animate_width_to (int width)
    {
        _target_width = width;
        if (_target_width == _current_width)
        {
            if (_width_animation_id > 0)
            {
                Source.remove (_width_animation_id);
                _width_animation_id = 0;
            }
            return;
        }

        _animation_start_width = _current_width;
        _animation_end_width = _target_width;
        _animation_start_us = GLib.get_monotonic_time ();
        int distance = _animation_end_width - _animation_start_width;
        if (distance < 0)
            distance = -distance;
        distance = int.max (1, distance);
        _animation_duration_ms = (uint) int.min (
            (int) WIDTH_ANIMATION_MAX_MS,
            int.max ((int) WIDTH_ANIMATION_MIN_MS, distance * 2)
        );

        if (_width_animation_id > 0)
            return;

        _width_animation_id = Timeout.add (WIDTH_ANIMATION_INTERVAL_MS, () =>
        {
            int64 elapsed_us = GLib.get_monotonic_time () - _animation_start_us;
            double progress = (double) elapsed_us / ((double) _animation_duration_ms * 1000.0);
            if (progress >= 1.0)
                progress = 1.0;
            if (progress < 0.0)
                progress = 0.0;

            // Smoothstep easing to reduce visible snap while shrinking.
            double eased = progress * progress * (3.0 - 2.0 * progress);
            _current_width = (int) Math.round (
                _animation_start_width + ((_animation_end_width - _animation_start_width) * eased)
            );

            set_size_request (_current_width, -1);

            if (progress >= 1.0)
            {
                _current_width = _animation_end_width;
                set_size_request (_current_width, -1);
                _width_animation_id = 0;
                return Source.REMOVE;
            }

            return Source.CONTINUE;
        });
    } // animate_width_to
} // CyclingRevealLabel
