/**
 * SPDX-FileCopyrightText: Copyright © 2020-2024 Louis Brauer <louis@brauer.family>
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */


/**
 * @class AboutDialog
 * @brief A dialog displaying information about the Tuner application.
 *
 * This class creates an "About" dialog with details such as the application's
 * version, authors, translators, license, and website.
 *
 * @extends Gtk.AboutDialog
 */
public class Tuner.Widgets.AboutDialog : Gtk.AboutDialog {
    /**
     * @brief Constructs a new AboutDialog.
     * @param window The parent window for this dialog.
     */
    public AboutDialog (Gtk.Window window) {
        Object ();
        set_destroy_with_parent (true);
        set_transient_for (window);
        set_modal (true);

		artists            = {"https://faleksandar.com/"};
		authors            = {"Louis Brauer, technosf"};
		documenters        = null;
		translator_credits = """Estonian tranlation by jrthwlate https://hosted.weblate.org/user/jrthwlate/
French translation by NathanBnm https://github.com/NathanBnm
and David D. https://hosted.weblate.org/user/dadu042
Italian translation by DevAlien https://github.com/DevAlien
and albanobattistella https://github.com/albanobattistella
Dutch translation by Vistaus https://github.com/Vistaus
Turkish translation by safak45x https://github.com/safak45x
Swedish translation by bittin https://github.com/bittin""";
		logo_icon_name     = app().get_application_id ()+"-scalable";
	//	logo_icon_name     = app().get_application_id ();
		program_name       = "Tuner";
		comments           = "Find & listen to Internet radio stations";
		copyright          = "Copyright © 2020-2024 Louis Brauer\nCopyright © 2024 technosf https://github.com/technosf";
		version            = @"v$(VERSION)";

		license      = """* Copyright (c) 2020-2024 Louis Brauer <louis@brauer.family>, 
        Copyright © 2024 technosf <https://github.com/technosf>

        Tuner is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Tuner is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Tuner.  If not, see <http://www.gnu.org/licenses/>.""";
        wrap_license = true;

		website       = "https://github.com/tuner-labs/tuner";
		website_label = "Tuner on Github";

		response.connect ((response_id) => {
			if (response_id == Gtk.ResponseType.CANCEL || response_id == Gtk.ResponseType.DELETE_EVENT)
			{
				hide_on_delete ();
			}
		});
	}
}
