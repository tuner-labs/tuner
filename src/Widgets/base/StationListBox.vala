/*
 * SPDX-FileCopyrightText: 2020-2022 Louis Brauer <louis@brauer.family> 
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using Gtk;
using Gee;
using Tuner.Models;
using Tuner.Widgets.Granite;

/**
 * @file StationListBox.vala
 * @brief Defines the StationListBox widget for displaying content with a header and action button.
 *
 * This file contains the implementation of the StationListBox class, which is a custom
 * Gtk.Box widget used to display content with a header, optional icon, and an
 * optional action button. It provides a flexible layout for presenting various
 * types of content within the Tuner application.
 *
 * @namespace Tuner
 */
namespace Tuner.Widgets.Base
{
    public interface StationListHookup : Object
    {
        public abstract void station_list_hookup( StationList station_list );
    } // StationListHookup
    

    /**
    * @class StationListBoxFactory
    * @brief Factory for StationListBox instances.
    */
    public class StationListBoxFactory
    {
        public static StationListBox create(StationListBoxConfig cfg)
        {
            var prepopulated = cfg.stations != null;
            var slb = new StationListBox(
                cfg.stack,
                cfg.source_list,
                cfg.category,
                cfg.name,
                cfg.icon,
                cfg.title,
                cfg.subtitle,
                prepopulated,
                cfg.station_set,
                cfg.action_tooltip_text,
                cfg.action_icon_name
            );

            cfg.stack.add_named (slb, cfg.name);

            if (cfg.stations != null)
            {
                var slist = StationList.with_stations (cfg.stations);
                if (cfg.station_list_hookup != null)
                {
                    slb.attach_station_list (cfg.station_list_hookup, slist);
                }
                else
                {
                    slb.content = slist;
                }
            }

            return slb;
        }
    } // StationListBoxFactory


    /**
    * @class StationListBox
    * @brief A custom Gtk.Box widget for displaying content with a header and action button.
    *
    * The StationListBox class is a versatile widget used to present various types of content
    * within the Tuner application. It features a header with an optional icon and action
    * button, and a content area that can display different views based on the current state.
    *
    * @extends Gtk.Box
    */
    public class StationListBox : Gtk.Box {

        /**
        * @property header_label
        * @brief The label displayed in the header of the ContentBox.
        */
        //  public HeaderLabel header_label;

        public Button tooltip_button { get { return _header_view.tooltip_button; } }
        public StationListBoxPager pager { get; private set; }
        public StationListItem item { get; private set; }
        public uint item_count { get; private set; }
        public string parameter { get; set; default = ""; }

        /**
        * @brief Updates the badge text for the source list item
        * @param badge The text to display in the badge
        */
        public void badge (string badge)
        {
            item.badge = badge;
        } // badge
        

        /**
        * @signal action_button_activated_sig
        * @brief Emitted when the action button is clicked.
        */
        public signal void action_button_activated_sig ();


        /**
         * Signal emitted when the number of items in the list changes.
         *
         * @param item_count The new number of items in the list
         * @param parameter Additional parameter that provides context for the change
         */
        public signal void item_count_changed_sig ( uint item_count, string? parameter );


        // -----------------------------------
        
        private SourceList.ExpandableItem _category;
        private ThemedIcon _icon;
        private StationListBoxHeader _header_view;
        private StationListBoxContent _content_view;
        private Stack _stack;
        private SourceList _source_list;


        
        /**
        * @brief Constructs a new ContentBox instance.
        *
        * @param icon The optional icon to display in the header.
        * @param title The title text for the header.
        * @param subtitle An optional subtitle to display below the header.
        * @param action_icon_name The name of the icon for the action button.
        * @param action_tooltip_text The tooltip text for the action button.
        */
        internal StationListBox (
            Stack stack,
            SourceList source_list,
            SourceList.ExpandableItem category,
            string name,
            string icon,
            string title,
            string subtitle,
            bool prepopulated = false,
            StationSet? data,
            string? action_tooltip_text,
            string? action_icon_name) 
        {
            Object (
                name:name,
                orientation: Orientation.VERTICAL,
                spacing: 0
            );

            //  get_style_context().add_class("station-list-box");
            
            _stack = stack;
            _source_list = source_list;
            _category = category;

            pager = new StationListBoxPager (data);
            _icon = new ThemedIcon (icon);
            
            item = new StationListItem (title, this, prepopulated);
            item.tooltip = subtitle;
            item.icon = _icon;
            item.set_data<string> ("stack_child", name);  

            _header_view = new StationListBoxHeader (subtitle, action_tooltip_text, action_icon_name);
            _header_view.action_activated.connect (() => { action_button_activated_sig (); });
            _header_view.set_parameter (parameter);
            notify["parameter"].connect (() =>
            {
                _header_view.set_parameter (parameter);
            });

            pack_start (_header_view, false, false);

            // -----------------------------------

            pack_start (new Separator (Orientation.HORIZONTAL), false, false);

            // -----------------------------------

            _content_view = new StationListBoxContent ();
            add (_content_view);
            
            show.connect (() => {   
                _content_view.show_content();            
            });

            map.connect (() => {
                source_list.selected = item;
            });

            category.add (item);  
        } // StationListBox

        
        /**
        * @brief Initializes the ContentBox instance.
        *
        * This method is called automatically by the Vala compiler and sets up
        * the initial style context for the widget.
        */
        construct {
            get_style_context ().add_class ("color-dark");
        } // construct


        /**
        * @brief Displays the alert view in the content area.
        */
        public void show_alert () {
            _content_view.show_alert ();
        } // show_alert


        /**
        * @brief Displays the "nothing found" view in the content area.
        */
        public void show_nothing_found () {
            _content_view.show_nothing_found ();
        } // show_nothing_found
        

        /**
        * @brief Removes this StationListBox from the stack and category
        */
        public void delist()
        {
            _stack.remove(this);
            _category.remove (item);
            tooltip_button.sensitive = false;
        } // delist


        /**
        * @property content
        * @brief Gets or sets the content list displayed in the ContentBox.
        *
        * When setting this property, it replaces the current content with the new
        * AbstractContentList and emits the content_changed_sig signal.
        */
        public ListFlowBox content { 
            set {
                _content_view.set_content (value);
                item_count = _content_view.content_list.item_count;
                item_count_changed_sig(item_count, parameter);
                show_all ();
            }

            get {
                return _content_view.content_list; 
            }
        } // content


        /**
        * @brief Hooks up and assigns a StationList to this box.
        */
        internal void attach_station_list (StationListHookup slh, StationList slist)
        {
            slh.station_list_hookup (slist);
            content = slist;
        } // attach_station_list

    } // StationListBox

} // Tuner
