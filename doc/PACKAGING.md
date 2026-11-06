<!--
Copyright © 2026 <https://github.com/technosf>
SPDX-FileCopyrightText: © 2026 <https://github.com/technosf>

SPDX-License-Identifier: GPL-3.0-or-later
-->

# Packaging Tuner for Various Platforms

The **flathub** packaging for **Tuner** is documented in <RELEASE.md>

How Tuner's repositories and packaging could be organised across channels (Flathub, Windows, distro packages, mobile) is proposed in <PACKAGING_STRATEGY.md>.

Other packaged versions of Tuner maybe available, but are maintained outside of Tuner itself; Versions may be out of date.

If you are packaging **Tuner** please contribute to this page.

## Arch Linux / AUR

Arch-based GNU/Linux users can find `Tuner` under the name [tuner-git](https://aur.archlinux.org/packages/tuner-git/) in the **AUR**:

```bash
yay -S tuner-git
```

Thanks to [@btd1377](https://github.com/btd1337) for supporting Tuner on Arch Linux!

## MX Linux

MX Linux users can find `Tuner` by using the MX Package Installer (currently under the MX Test Repo tab for MX-19 and the Stable Repo for MX-21)

Thanks to SwampRabbit for packaging Tuner for MX Linux!

## Pacstall

Pacstall is a totally new package manager for Ubuntu that provides an AUR-like community-driven repo for package builds.

If you already use `pacstall` you can install Tuner:

```bash
pacstall -I tuner
```

If you have Ubuntu and want a clean build of Tuner on your system, consider using `pacstall` instead of Flatpak if you don't feat beta software. Get `pacstall` here:

<https://pacstall.dev>
