/*
 * SPDX-FileCopyrightText: 2020-2022 Louis Brauer <louis@brauer.family>
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using Gtk;
using Tuner.Widgets.Granite;

namespace Tuner.Widgets.Base  // FIXME Refactor content out to a model - can it be shard with search?
{
    /**
    * @class StationListBoxContent
    * @brief Content stack for StationListBox.
    */
    public class StationListBoxContent : Gtk.Stack
    {
        /** @brief Duration of the fade-in when a list first fills the page */
        private const uint CONTENT_FADE_IN_MS = 400;

        private Box _content;
        private ListFlowBox _content_list;

        public ListFlowBox content_list { get { return _content_list; } }

        /**
         * @brief Creates the stack with its alert, nothing-found and content pages.
         */
        public StationListBoxContent()
        {
            Object ();

            var alert = new AlertView (
                _("Nothing here"),
                _("Something went wrong loading radio stations data from station provider. Please try again later."),
                "dialog-warning"
            );
            //  /*
            //  alert.show_action ("Try again");
            //  alert.action_activated.connect (() => {
            //      realize ();
            //  });
            //  */

            add_named (alert, "alert");

            var no_results = new AlertView (
                _("No stations found"),
                _("Please try a different search term."),
                "dialog-warning"
            );
            add_named (no_results, "nothing-found");

            _content = base_content();
            add_named (content_scroller(_content), "content");
        }

        /**
         * @brief Shows the load-error page.
         */
        public void show_alert ()
        {
            set_visible_child_full ("alert", StackTransitionType.NONE);
        }

        /**
         * @brief Shows the nothing-found page.
         */
        public void show_nothing_found ()
        {
            set_visible_child_full ("nothing-found", StackTransitionType.NONE);
        }

        /**
         * @brief Shows the content page.
         */
        public void show_content ()
        {
            set_visible_child_full ("content", StackTransitionType.NONE);
        }

        /**
         * @brief Replaces the content page's list and shows it.
         *
         * @param content The list to show. The previous list is destroyed.
         */
        public void set_content (ListFlowBox content)
        {
            var first_list = _content_list == null;     // Later refreshes (a star, a shuffle) replace it without a fade

            foreach (var child in _content.get_children ()) { child.destroy (); }

            _content_list = content;
            _content.add (_content_list);   
            show_content ();
            show_all ();

            if (first_list)
                Tuner.fade_in_widget (_content, CONTENT_FADE_IN_MS);     // Stations arrive gently, not in a flash
        }

        private static Box base_content()
        {
            var content = new Box (Orientation.VERTICAL, 0);
            content.get_style_context ().add_class ("color-light");
            content.valign = Align.START;
            content.get_style_context().add_class("welcome");
            return content;
        }

        private static ScrolledWindow content_scroller(Gtk.Box content)
        {
            var scroller = new ScrolledWindow (null, null);
            scroller.hscrollbar_policy = PolicyType.NEVER;
            scroller.add (content);
            scroller.propagate_natural_height = true;
            return scroller;
        }
    } // StationListBoxContent
} // Tuner
