# Copyright © 2026 <https://github.com/technosf>
# SPDX-FileCopyrightText: © 2026 <https://github.com/technosf>
#
# SPDX-License-Identifier: GPL-3.0-or-later
#

##
## Tuner main meson build file
##

## Project name, programming language and version
project (
    'io.github.tuner_labs.tuner',
    'vala', 'c',
    version: '2.1.1-beta.1',
    meson_version: '>= 1.3.2',
)

message('Starting build for project: ' + meson.project_name())

##
## Local debug build - let vala compiler know
##

message('opts: ' + get_option('debug').to_string() + ' prefix: ' + get_option('prefix')+ ' prefix check: ' + (get_option('prefix') != '/app').to_string()  )

vala_args = []

debug_local = get_option('debug') and get_option('prefix') != '/app'
if debug_local
  message('DEBUG_LOCAL')
  vala_args += ['--define=DEBUG_LOCAL']
endif

##
##


message('Build type: ' + get_option('buildtype'))


## Imports

i18n = import ('i18n') # Translation module
gnome = import('gnome') # GNOME module
fs = import('fs')   # Filesystem


##
## Translations and i18n handling
##

po_script = join_paths(meson.global_source_root(),'scripts','merge-po.sh')

if fs.exists(po_script)
  message('Running PO merge hook...')
  run_command(po_script, check: true)
endif

subdir ('po')


## Project arguments
add_project_arguments (
    '-DGETTEXT_PACKAGE="@0@"'.format (meson.project_name ()),
    language: 'c'
)

config_data = configuration_data()

#
# Enable local debug of translations if we're doing a local debug build
#
if debug_local

    ## Local debug build, install translations to build dir
    config_data.set_quoted('LOCALEDIR', join_paths(meson.global_build_root(), 'po'))

else

    ## Everything else, install translations to prefix
    config_data.set_quoted('LOCALEDIR', join_paths(get_option('prefix'), get_option('localedir')))

endif

config_data.set_quoted('GETTEXT_PACKAGE', meson.project_name())
config_data.set_quoted('VERSION', meson.project_version())
config_file = configure_file(
    input: 'src/Config.vala.in',
    output: '@BASENAME@',
    configuration: config_data
)

##
## Compiling resources
##
asresources = gnome.compile_resources (
    'as-resources',
    join_paths ('data', meson.project_name ()) + '.gresource.xml',
    source_dir: 'data',
    c_name: 'as'
)

##
## Listing dependencies
##
dependencies = [
    dependency ('glib-2.0'),
    dependency ('gtk+-3.0'),
    dependency ('gee-0.8'),
    dependency ('gio-2.0'),
    dependency ('gstreamer-1.0'),
    dependency ('gstreamer-player-1.0'),
    dependency ('libsoup-3.0'),
    dependency ('json-glib-1.0')
]

cc = meson.get_compiler('c')
dependencies += cc.find_library('m', required: true)

subdir ('src')

##
## Executable
##
executable (
    meson.project_name (),
    asresources,
    config_file,
    sources,
    dependencies: dependencies,
    vala_args: vala_args + ['--pkg', 'posix'],
    install: true
)

subdir ('data')

message('Build for project: ' + meson.project_name() + ' finished.\n')
