/*
 * SPDX-FileCopyrightText: 2020-2022 Louis Brauer <louis@brauer.family>
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using Gee;
using Gtk;
using Tuner.Models;
using Tuner.Widgets.Base;
using Tuner.Widgets.Granite;

namespace Tuner.Models
{
    /**
    * @class StationListBoxConfig
    * @brief Configuration for creating a StationListBox.
    */
    public class StationListBoxConfig : Object
    {
        public Stack stack { get; construct; }
        public SourceList source_list { get; construct; }
        public SourceList.ExpandableItem category { get; construct; }
        public string name { get; construct; }
        public string icon { get; construct; }
        public string title { get; construct; }
        public string subtitle { get; construct; }

        public StationSet? station_set { get; set; }
        public StationListHookup? station_list_hookup { get; set; }
        public Collection<Station>? stations { get; set; }
        public string? action_tooltip_text { get; set; }
        public string? action_icon_name { get; set; }

        public StationListBoxConfig(
            Stack stack,
            SourceList source_list,
            SourceList.ExpandableItem category,
            string name,
            string icon,
            string title,
            string subtitle)
        {
            Object (
                stack: stack,
                source_list: source_list,
                category: category,
                name: name,
                icon: icon,
                title: title,
                subtitle: subtitle
            );
        }
    } // StationListBoxConfig
} // Tuner
