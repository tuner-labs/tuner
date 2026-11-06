<!--
Copyright © 2026 <https://github.com/technosf>
SPDX-FileCopyrightText: © 2026 <https://github.com/technosf>

SPDX-License-Identifier: GPL-3.0-or-later
-->

# ![icon](docs/logo_01.png) Develop, Build and Contribute to Tuner [![License: GPL v3](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](http://www.gnu.org/licenses/gpl-3.0) <!-- omit in toc -->

Discover and Listen to your favourite internet radio stations, and add improve the code!

- [Overview](#overview)
- [TL;DR](#tldr)
- [Prerequisites](#prerequisites)
  - [Naming Conventions](#naming-conventions)
  - [Dependencies](#dependencies)
- [Tuner Development Lifecycle](#tuner-development-lifecycle)
  - [Building Tuner From Source](#building-tuner-from-source)
  - [Valadoc](#valadoc)
- [Building the Tuner Flatpak](#building-the-tuner-flatpak)
- [Readying code for a Pull Request](#readying-code-for-a-pull-request)
  - [Build Changes](#build-changes)
  - [Language Changes & Translations](#language-changes--translations)
  - [Code Changes](#code-changes)
- [Debugging](#debugging)
  - [VSCode](#vscode)
  - [Bug Introduction Deduction](#bug-introduction-deduction)
- [Release Process](#release-process)

## Overview

**_Tuner_** is hosted on [Github](https://github.com/tuner-app/tuner), packaged as a Flatpak and distributed by Flathub. **_Tuner_** is written in [Vala](https://vala.dev/), a C#/Java/JavaFX-like language with a self-hosting compiler that generates C code, uses the GObject type system and wrapping a number of GTK libraries, and utilizes GNOME internationalization and localization (_i18n_) for user-facing strings, which are translated via [Weblate](https://hosted.weblate.org/projects/tuner/). [Meson](https://mesonbuild.com/) is the build system.

## TL;DR

```bash
gh repo clone yourusername/tuner
cd tuner
checkout development
meson setup --buildtype=debug builddir
meson compile -C builddir
./builddir/io.github.tuner_labs.tuner
flatpak-builder --force-clean --user --sandbox --install build-dir io.github.tuner_labs.tuner.yml
flatpak --user run io.github.tuner_labs.tuner
```

## Prerequisites

### Licenses

_Tuner_ is licensed under **GPL-3.0-or-later**
Compliance can be checked using [Reuse](https://reuse.software/) linter:

```bash
reuse lint
```

### Naming Conventions

Going forward, all new code should conform to the following naming conventions:

- Namespaces are named in camel case: NameSpaceName
- Classes are named in camel case: ClassName
- Method names are all lowercase and use underscores to separate words: method_name
- Constants (and values of enumerated types) are all uppercase, with underscores between words: CONSTANT_NAME
- Public properties are named in camel case: propertyName
- Private member variables are named all lowercase and use underscores to separate words prefixed with an underscore: _var_name

<!---- Signals are named all lowercase and use underscores to separate words postfixed with \_sig: propertyName_sig -->

### Dependencies

Development dependencies for Tuner are:

```bash
gstreamer-1.0
gstreamer-player-1.0
gtk+-3.0
json-glib-1.0
libgee-0.8
libqrencode
libsoup-3.0
librsvg2-dev
meson
vala
```

Install required dependencies (Debian/Ubuntu):

```bash
sudo apt install git valac meson
sudo apt install libgtk-3-dev libgee-0.8-dev libgstreamer1.0-dev libgstreamer-plugins-bad1.0-dev libsoup-3.0-dev libjson-glib-dev librsvg2-dev libqrencode-dev
```

[libgee](https://gitlab.gnome.org/GNOME/libgee/-/releases) is built as a module during the build.


## Tuner Development Lifecycle

Hosted on Github, the _main_ branch reflects captured the current release and tags. The _development_ branch is the destination for in progress code, translations and where releases are staged. Fork the project and develop on your forks' _development_ branch. All _Pull Requests_ should be made against the _development_ branch.

The development lifecycle is:

- Build Tuner from Source
  - Checkout _development_ branch
  - Setup the build
  - Local build and confirm
- Update the Code
  - Modify code
  - Local build
  - Test
  - Flatpak Build
  - Local Flatpak User build and test
  - Github Flatpak build and test
  - Pull Request

### Building Tuner From Source

After Forking your own copy of the Tuner project from [https://github.com/tuner-labs/tuner](https://github.com/tuner-labs/tuner), _clone_ your copy to your development machine then checkout the development branch:

```bash
gh repo clone yourusername/tuner
cd tuner
checkout development
```

There are two build configurations: _debug_ and _release_. The _debug_ build (manifest _io.github.tuner_labs.tuner.debug.yml_) is recommended for development, while the _release_ build (manifest _io.github.tuner_labs.tuner.yml_) is for distribution. Build instructions will focus on the _debug_ build. Copy the required manifest to _io.github.tuner_labs.tuner.xml_ before building.

Clone the repo and drop into the Tuner directory:

```bash
git clone https://github.com/tuner-app/tuner.git
cd tuner
```

Configure Meson for development debug build, build Tuner with Ninja, and run the result:

```bash
meson setup --buildtype=debug builddir -Dtranslate=update
meson compile -C builddir
meson install -C builddir     # only needed once to get the gschema in place
./builddir/io.github.tuner_labs.tuner
```

Tuner can be deployed to the local system to bypass flatpak if required, however it is _recommended to use flatpak_.To do deploy locally, run the following command:

```bash
meson configure -Dprefix=/usr
sudo ninja install
```

### Valadoc

```bash
valadoc --force \
  --pkg gtk+-3.0 --pkg glib-2.0 \
  --pkg gee-0.8 --pkg gio-2.0 \
  --pkg libsoup-3.0 --pkg json-glib-1.0 \
  --pkg gstreamer-1.0 --pkg gstreamer-player-1.0 \
  --package-name=Tuner \
  --directory=src \
  -o apidocs \
  --verbose
  $(find src -type f -name '*.vala')
```

## Local Build and Test

meson compile -C builddir
meson compile -C builddir export-and-compile-local-schemas
GSETTINGS_SCHEMA_DIR="builddir/data" ./builddir/io.github.tuner_labs.tuner
gdb -ex "set environment GSETTINGS_SCHEMA_DIR=builddir/data" -ex run -ex bt --args ./builddir/io.github.tuner_labs.tuner


## Building the Tuner Flatpak

Tuner uses the **org.freedesktop.Sdk** version **25.08** with the  **Vala** extension ([releases here](https://gitlab.com/freedesktop-sdk/freedesktop-sdk/-/releases)).
To build the tuner flatpak, install the freedesktop SDK, Platform and Vala extension. For example, for x86:

```bash
apt-get install flatpak-builder
flatpak install flathub org.freedesktop.Platform//x86_64//25.08
flatpak install flathub org.freedesktop.Sdk//x86_64//25.08
flatpak install flathub org.freedesktop.Sdk.Extension.vala/x86_64/25.08
```

Build the flatpak in the _user_ scope with and without debug:

```bash
flatpak-builder --force-clean --user --sandbox --install build-dir io.github.tuner_labs.tuner.debug.yml

flatpak-builder --force-clean --user --sandbox --install build-dir io.github.tuner_labs.tuner.yml
```

Run the Tuner flatpak:

```bash
flatpak --user run io.github.tuner_labs.tuner
```

Check the app version to ensure that it matches the version in the manifest.

## Readying code for a Pull Request

### Build Changes

If the build has changed it may be required to update repository check-in **Action** workflows in the _.github_ directory prior to check-in. For example if the _Platform_ changes the Repository _Build and Test_ and _CI_ actions need to be updated and pushed prior to code changes are pushed. It is also good practice to check to see if the action components themselves have been superseded and need to reference new versions.

### Language Changes & Translations

Changes to strings that are internationalized require translation via [Weblate](https://hosted.weblate.org/projects/tuner/) and reintegration of the new translations, the .po files, into the build via a Weblate pull request.

If translatable strings have been update for translation by GNOME gettext require that the _.pot_ file be regenerated, checked in and pushed to the development branch for Weblate to pick them up. If _Countries_ or _Languages_, or if other strings in the _Application_ have changed, or if the package _extra_ metadata has changed, the regeneration commands are:

```bash
meson compile -C builddir countries-pot
meson compile -C builddir application-pot
meson compile -C builddir extra-pot
```

If the _.po_ files change, the meson build setup should be rerun.

### Code Changes

Before a pull request can be accepted, the code must pass linting. This is done by running the following command:

```bash
flatpak run --command=flatpak-builder-lint org.flatpak.Builder manifest io.github.tuner_labs.tuner.yml
```

Linting currently produces the following issues (addressed in ticket #140):

```json
{
    "errors": [
        "appid-uses-code-hosting-domain"
    ],
    "info": [
        "appid-uses-code-hosting-domain: github.com"
    ],
    "message": "Please consult the documentation at https://docs.flathub.org/docs/for-app-authors/linter"
}
```

Ensure that the CI checks pass before pushing your changes.

## Debugging

### VSCode

Debugging from VSCode using GDB, set up the launch.json file as follows:

```json
{
  "version": "0.2.0",
  "configurations": [    
    {
      "name": "Debug Vala with Meson",
      "type": "cppdbg",
      "request": "launch",
      "program": "${workspaceFolder}/builddir/io.github.tuner_labs.tuner",
      "args": [],
      "stopAtEntry": false,
      "cwd": "${workspaceFolder}",
      "environment": [],
      "externalConsole": false,
      "MIMode": "gdb",
      "miDebuggerPath": "/usr/bin/gdb",
      "setupCommands": [
        {
          "description": "Enable pretty-printing for gdb",
          "text": "-enable-pretty-printing",
          "ignoreFailures": true
        }
      ],
      "preLaunchTask": "meson build"
    }
  ]
}
```

_Note:_ Variables appear as pointers, and generated code is not found. Please submit a better config if you have one.

### Bug Introduction Deduction

Knowing when a bug was introduced requires building previous versions and looking for the aberrant behavior. The following commands can be used to check out previous versions of the code:

```bash
git fetch
git tag
git checkout <tag>
```

After checking out the required version, build and run the app as described above.

## Flathub Screenshots

Flathub wants real window screenshots: just the app window with its title bar, rounded corners and shadow, default
theme and settings, no desktop behind it, 1000x700 or smaller, with a one-sentence caption each (see its
[quality guidelines](https://docs.flathub.org/docs/for-app-authors/metainfo-guidelines/quality-guidelines)).

Local debug builds (`meson setup builddir --buildtype=debug` with a prefix other than `/app`) include a
screenshot mode, `src/Services/ScreenshotMode.vala`, that puts the app into a known state. It is not compiled into
release or Flatpak builds. Two scripts do the rest:

* `scripts/screenshots.sh` runs the app once per preset in a throw-away sandbox (its own settings, data, cache and
  D-Bus session, so none of your favourites, history or settings show and nothing is saved) on a private virtual
  display (Xvfb), so no desktop, panel, terminal or mouse pointer can appear in a shot. It uses the stock Adwaita
  theme, captures the virtual screen and writes one raw capture per preset to `flathub/shots/raw`.
* `scripts/flathub_screenshots.py` crops each capture to the window, trims its outline, adds the rounded corners and
  drop shadow, scales to at most 1000 px wide, writes `flathub/shots/ready` and prints the metainfo `<screenshots>`
  block.

### Taking the shots

```
sudo apt install xvfb imagemagick python3-pil   # once
meson compile -C builddir                       # rebuild after any change to the app

# Stations used in the shots (see below)
export TUNER_SHOT_STATION=aa01e1f5-9bb0-4cc1-a77d-88c3c2e712d4
export TUNER_SHOT_STARRED=dad48711-7228-4dce-a06b-c5499167e522,961949f3-0601-11e8-ae97-52543be04c81,60ceaabd-4efd-4f47-b961-0dab6f475731,6efe216d-bf7e-11e9-8502-52543be04c81

# 1. Capture. Do not edit the script while it runs.
scripts/screenshots.sh

# 2. Crop, shadow, scale, metainfo block. Output goes to flathub/shots/ready.
#    (screenshots.sh already does this with these values; run it again to change them)
python3 scripts/flathub_screenshots.py --crop bg --inset 5 --add-shadow \
    --shadow-radius 30 --shadow-offset 0 --shadow-opacity 255 --corner-radius 15 \
    --prefix Tuner.220. --captions flathub/captions.txt \
    -o flathub/shots/ready flathub/shots/raw/*.png
```

`screenshots.sh` runs step 2 itself, so a plain `scripts/screenshots.sh` already produces the finished set: the
defaults are the values above (inset 5, shadow radius 30, offset 0, opacity 255, corner radius 15). Run step 2 by
hand to repeat it on the existing raw captures, or with other shadow settings, without capturing again.
`scripts/screenshots.sh -n` captures only. `scripts/screenshots.sh -l` lists the presets, and
`scripts/screenshots.sh discover dark` runs just those.

Presets, in the order they run: `discover`, `trending`, `search`, `starred` (with the Preferences popover open),
`jukebox` (activates Jukebox, waits for a station to be picked), `offline`, `dark`, and `history` last (plays the
starred stations in turn so the History list has several tracks). `history` and the shots that show a playing
station need `TUNER_SHOT_STATION`; `starred` needs `TUNER_SHOT_STARRED`.

### Stations

* `TUNER_SHOT_STATION` is the first playing station. `TUNER_SHOT_STARRED` is a list of stations that are starred in
  the `starred` shot and played in turn for the History list.
* Each shot that shows a playing station takes the next station from the pool: `TUNER_SHOT_STATIONS` if set,
  otherwise `TUNER_SHOT_STATION` followed by the starred ones. Add more to `TUNER_SHOT_STATIONS` so that no two shots
  show the same station.
* Station uuids can be found with `https://de2.api.radio-browser.info/json/stations/search?name=...`.

### Shadow and size options

| Option | Default | What it does |
| :- | :- | :- |
| `--crop bg` | | crop to the window and any popover on the virtual display |
| `--inset N` | 0 (`screenshots.sh` uses 5) | trim N px from every side, removing the window outline |
| `--add-shadow` | | draw rounded corners and a drop shadow (the virtual display has no compositor, so GTK draws none) |
| `--shadow-radius N` | 30 | softness and width of the shadow, px |
| `--shadow-offset N` | 0 | how far the shadow is shifted down, px; 0 gives an even glow |
| `--shadow-opacity N` | 255 | darkness of the shadow, 0-255 |
| `--corner-radius N` | 15 | window corner radius, px |
| `--max-width N` / `--min-width N` | 1000 / 700 | scale down above, warn below |

`screenshots.sh` environment: `TUNER_SHOT_SIZE` (window, default `1000x625`), `TUNER_SHOT_SCALE` (1 or 2),
`TUNER_SHOT_CANVAS`, `TUNER_SHOT_GTK_THEME`, `TUNER_SHOT_ICON_THEME`, `TUNER_SHOT_FONT`, `TUNER_SHOT_INSET`,
`TUNER_SHOT_HISTORY`, `TUNER_SHOT_HISTORY_DWELL` and `TUNER_SHOT_WM` (try a window manager if shots come out blank).
They are documented at the top of the script.

### Publishing

Copy `flathub/shots/ready/Tuner.220.*.png` to where the metainfo URLs point, paste the printed `<screenshots>` block
into `data/io.github.tuner_labs.tuner.metainfo.xml.in` (best shot first), and run `appstreamcli validate`.
Captions come from `flathub/captions.txt` (`file.png = One sentence, no full stop`).

### By hand

To drive the app yourself, set `TUNER_SCREENSHOT` (keys: `size`, `theme`, `layout`, `offline`, `starred`, `station`,
`view`, `activate`, `activate_wait`, `history`, `history_dwell`, `search`, `popover`, `delay`, `popover_delay`;
documented at the top of `ScreenshotMode.vala`) and run with `GSETTINGS_BACKEND=memory`. Only the close button is
shown in the title bar by default.

Station names and titles come live from radio-browser.info, so check every image before publishing it: no rude names
and no personal data.

## Release Process

Cutting a releasing **Tuner** on [github](https://github.com/tuner-labs/tuner) and packaging and pushing out a new **Flathub** distribution are covered in the [release doc](RELEASE.md)
