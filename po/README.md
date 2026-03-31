<!--
SPDX-FileCopyrightText: © 2026 <https://github.com/technosf>

SPDX-License-Identifier: GPL-3.0-or-later
-->

# Translations (Portable Objects)

This document explains how translation targets in `po/` are generated, what each build step produces, and the recommended command order for common tasks. ✅

---

## Overview 🔧

- `po/` holds the project's translation build file and the subdirectories that hold the actual generated translated material which is installed by default
- `po/application/` contains the application translatable strings, catalog and linguas. They are not installed by default, but later combined with other translations into `po`.
- `po/countries/` contains country and language names, catalog and linguas. They are not installed by default, but later combined with other translations into `po`.
- `po/extra/` contains metadata catalog and linguas. They are installed by default.
- The translated `.po` files in `application`, `countries` and `extra` are provided by _Weblate_ via _git_ pull requests.
- Targets in the Meson build: generate a `.pot` template (optional), compile `.po` files to binary `.mo` files, and install `.mo` files into the configured `localedir`.
- In the Flatpak the different languages go into different `.Locale`s which are installed alongside the app dependent on the Locales in your environment.

## Typical command sequence (when translatable strings have changed) ▶️

1.  Regenerate the POT template [only when translatable strings have been updated in the app]:

    ```bash
    # Enable POT generation via Meson option, then run the pot target
    meson setup builddir -Dtranslation=update
    meson compile -C builddir application-pot
    meson compile -C builddir countries-pot
    meson compile -C builddir extra-pot
    ``` 

2.  Generate translations:
    - Git - Check in the `.pot` files into the tuner `development` branch
    - Update (Weblate)[https://hosted.weblate.org/projects/tuner/] from the Operation-Repository Maintanence menu
    - Translate the strings
    - Push the translations back to the tuner development branch

3.  Incorporate the updated translation  
    - Update your work folder from the `develoment` branch
    - `rm -r builddir` - clear the build
    - `meson setup builddir` will fire a hook that concatenates the `.po` files in `po/application` and `po/countries` into `po`

4. Compile translations (.po → .mo):
    - `meson compile -C builddir` fires of the meson gettext target in `po`, compiling the `.po`'s into `.mo`'s and installing them 


## Design Choices 🇺🇳

- The more volatile translatable strings in the application were split into two components:
    - `countries` constains the larger set of more static translatable strings
    - `application` contains the smaller set of more volatile strings in the UI
- Separate components simplifies the management of translations on Weblate
- Script `scripts\update-po.sh` concatenates `.po` files using `gettext msgcat` during setup
- A single `.po` per LINGUA means that only a single domain is needed in the code

## Debugging & troubleshooting ⚠️

- Missing tools: install the `gettext` package for your OS.
- No output for a language: ensure `po/LINGUAS` lists the language and `po/<lang>.po` exists.
- Check Meson's log: `builddir/meson-logs/meson-log.txt` for configure-time issues.
- To get more verbose Meson output: use `meson setup --log-level=debug` or consult `meson --help`.

---
