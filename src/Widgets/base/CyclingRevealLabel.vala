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
    private const int LABEL_WIDTH_MIN = 100;
    private const int LABEL_RESIZE_BUFFER = 10;
    //  private const int DISPLAY_WIDTH_OFFSET = 761;  
    //  private const int BORDER_WIDTH_OFFSET = 7;  

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

    private signal void flourish_complete_sig();

    private bool _metadata_fast_cycle;
    private int _last_parent_width = 0;  // tracks window width    private int _window_width_previous = 0;  // tracks window width
    private int _parent_unused_growth = 0; // Tracks the maximum width the label can occupy
    private int _min_label_width;    // Minimum label width
    private int _peak_label_width;    // Peak label width
    private bool _followed_width_change;    // Followed width
    //  private int _current_label_width;    // Current label width

    private uint _label_cycle_id = 0;
    private uint _flourish_id = 0;
    private int _min_count_down;
    private uint16 _display_seconds = 0;   // Mix up the cycle phase start point
    private uint16[] _cycle_phases_fast = {5,11,17,19,23}; // Fast cycle times - primes so everyone gets a chance
    private uint16[] _cycle_phases_slow = {23,37,43,47,53}; // Title, plus four subtitles
    private uint16[] _cycle_phases;  

    private Gee.Map<uint, string> sublabels = new Gee.HashMap<uint, string>();


    public CyclingRevealLabel (Widget follow, int min_label_width, string? str = null) 
    {
        Object();
        
        label_child.set_line_wrap(false);
        label_child.set_justify(Justification.CENTER);
        base.label_child.set_text( str); 
        
        _min_label_width =  min_label_width;

        follow.size_allocate.connect((widget, allocation) => 
        {
            if ( _last_parent_width == 0 ) _last_parent_width = allocation.width;
            var delta = allocation.width - _last_parent_width;

            if ( delta == 0 ) return;

            if ( delta > 0 ) 
            // Growing parent
            {
                _parent_unused_growth += delta;
            }
            else
            // Shrinking parent
            {
                if  ( -delta  <= _parent_unused_growth) 
                // Track the delta back
                {
                    debug(@"Shrink delta: $delta _parent_unused_growth: $_parent_unused_growth");
                    _parent_unused_growth += delta;
                    return;
                }

                debug(@"Delta: $delta  Peak old: $_peak_label_width new: $(_peak_label_width + delta + _parent_unused_growth)  follow: $_last_parent_width");
                _peak_label_width += ((2*delta) + _parent_unused_growth);
                _peak_label_width = int.max(_peak_label_width, LABEL_WIDTH_MIN);
                _parent_unused_growth = 0;
                set_size_request(_peak_label_width, -1);
                _followed_width_change = true;
            }
            _last_parent_width = allocation.width;         
        });

        size_allocate.connect((allocation) => 
        {
            if (!_followed_width_change && allocation.width <= ( _peak_label_width + LABEL_RESIZE_BUFFER )) 
            {
                _followed_width_change = false;
                return;
            }
            debug(@"Size Alloc:  $(allocation.width) Peak: $(_peak_label_width)");
            _peak_label_width = int.max(_peak_label_width,allocation.width - LABEL_RESIZE_BUFFER);
            set_size_request(9*_peak_label_width/10, -1);
        });

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
        

        // Make the peak width smaller than allocated by the apparent size of the boarder, plus a fudge
        //  _peak_label_width = int.max(_peak_label_width,get_allocated_width()-BORDER_WIDTH_OFFSET);

        debug(@"CL set text: $(base.get_text()) > $text");
        if ( base.set_text(text) )
        {

            debug(@"CL set text - Success: $text");
            // Measure the natural width of the label with the new text
            //  int min_width, natural_width;
            //  get_preferred_width(out min_width, out natural_width);

            //  // Update _max_label_width only if the new text exceeds it
            //  if (natural_width > _max_label_width) {
            //      _max_label_width = natural_width;
            //  }

            //  // Apply the new width constraints
            //  update_size(  );
            return true;
        }
        
        debug(@"CL set text - Failed: $text");
        return false;
     } // label


    //   /**
    //    */
    //   private void update_size(bool flourish = true) 
    //   {        
    //      if ( _flourish_id > 0 ) 
    //      {
    //          Source.remove(_flourish_id);
    //          _flourish_id = 0;
    //      }

    //      //  var size = int.max(int.min(_max_label_width, _peak_label_width),  _min_label_width );
    //      //  if ( size == _current_label_width ) return;
    //      //  if ( !flourish || size == _min_label_width  ) 
    //      //  {
    //      //      set_size_request( size, -1);
    //      //      _current_label_width = size;
    //      //      return;
    //      //  }

    //      // Flourish

  
    //      //  Idle.add (() => 
    //      //  // Initiate the fade out in another thread
    //      //  {
    //      //      _flourish_id = Timeout.add_full(Priority.DEFAULT, 3, () => 
    //      //      {  
    //      //          if ( _current_label_width >=  size ) 
    //      //          {
    //      //              _flourish_id = 0;
    //      //              flourish_complete_sig();
    //      //              return Source.REMOVE;
    //      //          }

    //      //          _current_label_width++;// += 4;
    //      //          set_size_request( _current_label_width, -1);
            
    //      //          return Source.CONTINUE; // Leave timer to be recalled
    //      //      });
    //      //      debug(@"Flourish target: $size  from: $_current_label_width id: $_flourish_id");
    //      //      return Source.REMOVE;
    //      //  });  
    //  } // update_size


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

        if ( _flourish_id > 0 ) 
        {
            Source.remove(_flourish_id);
            _flourish_id = 0;
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
        _peak_label_width = 0;
        set_size_request(LABEL_WIDTH_MIN, -1);
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
} // CyclingRevealLabel

