<!--
Copyright © 2026 <https://github.com/technosf>
SPDX-FileCopyrightText: © 2026 <https://github.com/technosf>

SPDX-License-Identifier: GPL-3.0-or-later
-->

# ![icon](flathub/logo_01.png) Tuner [![License: GPL v3](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](http://www.gnu.org/licenses/gpl-3.0) [![Translation status](https://hosted.weblate.org/widget/tuner/language-badge.svg) ![Translation status](https://hosted.weblate.org/widgets/tuner/-/tuner-ui/svg-badge.svg)](https://hosted.weblate.org/engage/tuner/)

## Discover and Listen to your favourite internet radio stations

Minimalist radio station player - **Tuner** Version 2

<p align="center">
  <img src="flathub/Tuner.210.one.png" width="600">
</p>

>I love listening to radio while I work. There are tens of thousands of cool internet radio stations available, however I find it hard to "find" new stations by using filters and genres. As of now, this little app takes away all the filtering and just presents me with new radio stations every time I use it.
>
>While I hacked on this App, I discovered so many cool and new stations, which makes it even more enjoyable. I hope you enjoy it too.

-- _**louis77**_

## Features

- Explore ever changing radio stations indexed in [radio-browser.info](https://www.radio-browser.info/)
- See the top selections of listened to and saved stations from the index
- Find different station content genres and subgenres from the index
- Jukebox - Play a new random station every ten minutes
- Save your favourite stations
- Search for stations and content by keyword
- Save your favorite station searches
- Export your favorite stations to _m3u_ playlists
- DBus integration to pause/resume playing and show station info in Wingpanel
- Updates station click count at station index on station play
- Updates station vote count at station index when you star a station

### Internationalization & Translation

**Tuner** is Internationalized, and is available in various languages. Translations are hosted on [Weblate](https://hosted.weblate.org/engage/tuner/). Please help by [translating Tuner into your language or fix any translation issues](doc/I18N.md) you find.

Thanks to the Weblate team for generously hosting **Tuner** for free!

### Recent Updates

_December 2025_ all things **Tuner** have become a _Github Organization_ called [**tuner_labs**](https://github.com/tuner-labs) to ensure **Tuner** continues to be available and we invite you to participate in keeping it a great source of music discovery and Internet Radio player.

_January 2025_ Version 2 released with major new features and performance improvements.

## Installation

**Tuner** is primarily [developed](doc/DEVELOP.md) and distributed as a Flatpak on [Flathub](https://flathub.org/apps/details/io.github.tuner_labs.tuner).

It can also be built and [distributed via other platforms and distros](doc/PACKAGING.md).
Please help make **Tuner** work on your favorite Distro/Package.

## Status and Support

Join in or start [discussion about tuner](https://github.com/orgs/tuner-labs/discussions)... Feature request, observations and Issues can be documented with tickets on [Github](https://github.com/tuner-labs/tuner/issues)

### Build, Maintenance and Development of Tuner

Building, developing and maintaining **Tuner** is detailed separately and in detail in the [DEVELOP](doc/DEVELOP.md) markdown.

### Known Issues

#### If AAC/AAC+ streams don't play (found on Elementary OS 6) install the following dependency

```bash
sudo apt install gstreamer1.0-libav
```

#### 'Failed to load module "xapp-gtk3-module"'

Running Tuner from the CLI with `flatpak run io.github.tuner_labs.tuner` may produce a message like the following:

`Gtk-Message: 10:01:00.561: Failed to load module "xapp-gtk3-module"`

This relates to Gtk looking for Xapp (which isn't used by Tuner) and can be ignored.

### Environment Variables

The radio station index server can be specified via and environmental variable at startup:

`TUNER_API` - a `:` separated list of API servers to read from, e.g.
_ `export TUNER_API="de1.api.radio-browser.info:nl1.api.radio-browser.info"; io.github.tuner_labs.tuner`

## Contribute

Help is appreciated:

- Deeper integration into the GNOME desktop environment (DBus and such)
- Development of new features for Tuner (skills: Vala/C)
- Create and maintain Tuner packages for distros. Do you know how we can get Tuner into some official repos?
- Help me fixing those Flatpak bugs users are reporting
- Translate Tuner into more languages

**Interested?** Please open an [issue](https://github.com/tuner-labs/tuner/issues), start a [discussion](https://github.com/orgs/tuner-labs/discussions) or offer up a [pull request](https://github.com/tuner-labs/tuner).

## Origin Story

>I've started `Tuner` in May 2020 when COVID-19 began to change our lives and provided me with some time to finally learn things that I couldn't during my life as a professional developer.
>
>I moved from macOS to Linux as a daily driver, learned a little about Linux programming, and chose Vala as the language for Tuner. At the time I was running elementary OS, and they have excellent documentation for beginning developers on how to build nice-looking apps for elementary. That helped me a lot to get started with all the new stuff.
>
>At the time, I never expected `Tuner` to be installed by the thousands on other great distros, like Arch, MX Linux, Ubuntu, Fedora. In August 2020, I released `Tuner` as a Flatpak app, and it was installed over 18.000 times on Flathub alone ever since! Users began to send me their appreciations but also bug reports and feature requests. Some friendly contributors made Tuner available on MX Linux and Arch AUR repos.
>
>Maybe it was around this time when I started to feel not only the euphoria that comes with Open Source projects but also the weight of responsibility. I feared to move on because I didn't want to break things, so _I_ took a break :-).
>
>Yet, users keep sending bug reports and feature requests. I want `Tuner` to live on and be the best tiny internet radio receiver for the Linux environment.

-- _**louis77**_

## Credits

- [technosf](https://github.com/technosf) Current maintainer and rewriter of a swarth of Tuner for V2
- [louis77](https://github.com/louis77) Originator and genius behind Tuner
- [@jrthwlate](https://hosted.weblate.org/user/jrthwlate/) - Estonian translation
- [@yakushabb](https://github.com/yakushabb) for flathub and flatpak config help
- [faleksandar.com](https://faleksandar.com/) for icons and colors
- [@NathanBnm](https://github.com/NathanBnm) - French translation
- [@DevAlien](https://github.com/DevAlien) - Italian translation
- [@albanobattistella](https://github.com/albanobattistella) - Italian translation
- [@Vistaus](https://github.com/Vistaus) - Dutch translation
- [@safak45x](https://github.com/safak45x) - Turkish translation
- [@btd1337](https://github.com/btd1337) - supports Tuner on Arch Linux / AUR
- [@SwampRabbit](https://github.com/SwampRabbit) - supports Tuner on MX Linux

## Disclaimer

Tuner uses the community-driven radio station catalog radio-browser.info. Tuner
is not responsible for the stations shown or the actual streaming audio content.

## Third-party code

This project contains small portions of code derived from the
Granite library (<https://github.com/elementary/granite>), used by
the elementary OS project.

The copied components remain licensed under the LGPL-3.0 and retain
their original copyright notices.
