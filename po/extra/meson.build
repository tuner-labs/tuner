## SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
## SPDX-License-Identifier: GPL-3.0-or-later
##
## @file meson.build
## @brief Install metadata translations
##
## 
#
# Metadata translations used by Flatpak and other packaging systems
# live under `po/extra/` and are kept separate from the main `po/` 
# catalogs to modularize the translation process by Weblate components.
#
#     meson compile -C builddir extra-pot
#


message('Extra translations...')

i18n.gettext ('extra',
  preset: 'glib',
  install: false
)

