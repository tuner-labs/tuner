##
## SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
## SPDX-License-Identifier: GPL-3.0-or-later
##
## @file meson.build
## @brief PO meson build file
##
## This file defines how translations are handled for the project, including:
## - inclusion of additional translation subdirectories
## - optional generation of POT templates (when updating translations)
## - compilation of .po files into .mo files and installation to the locale dir
## - calling Meson's i18n helper to gather and validate gettext resources
##

message('Installing translations...')


# - `application/` contains application translations and data
subdir('application') # Generate .po from the .pot, if needed


# - `countries/` contains country-specific translations and data
subdir('countries') # Generate .po from the .pot, if needed


# - `extra/` contains extra data
subdir('extra') # Generate .po from the .pot, if needed


message('Scanning gettext resources...') 


i18n.gettext(meson.project_name(),
  preset: 'glib',
  install: true
)

message('Installed translations')
