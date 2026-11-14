<!--
Copyright © 2026 <https://github.com/technosf>
SPDX-FileCopyrightText: © 2026 <https://github.com/technosf>

SPDX-License-Identifier: GPL-3.0-or-later
-->

# Repository and Packaging Structure

Status: **proposal**. Nothing here is implemented yet.

## 1. The idea in one paragraph

Tuner's **code** lives in one repository. Every way of **packaging or delivering** Tuner (Flatpak,
Windows, native Linux packages, a web app, mobile apps) lives in its own repository. A packaging
repository never contains Tuner's source. It names one released version of the source, fetches it,
builds it, and publishes the result. When Tuner releases a new version, each packaging repository is
updated to point at it.

```
                        tuner  (the code)
                  Vala source, Meson build, data,
                  translations, docs, native dev build
                              |
                     tagged release + source tarball
                              |
      +-----------+-----------+-----------+-----------+
      |           |           |           |           |
 tuner-flatpak  tuner-windows  tuner-linux  tuner-web   tuner-android / tuner-ios
 (Flathub)      (installer)   (deb/rpm/    (browser)    (separate apps,
                               arch/...)                 built from the spec)
```

## 2. Why separate them

- The code repo stays small and has one job: the app and a native build that proves it compiles.
- Packaging changes (a new runtime, a new installer, a distro policy change) do not touch the code
  history, and do not need a code release.
- Each channel can have its own maintainers, permissions, CI, issue tracker and release timing.
- Contributors who only care about the app never see packaging noise, and packagers never need write
  access to the code.

The cost is coordination: a change that spans code and packaging is two changes in two repositories.
Section 5 describes the rules that keep this manageable.

## 3. The repositories

All live under the `tuner-labs` organisation unless noted.

### 3.1 `tuner` - the code

**Contains**
- `src/`, `data/` (including icons, desktop file, metainfo, GSettings schema), `po/`, `vapi/`
- `meson.build`, `meson_options.txt`
- `doc/` (development, architecture, translation and this document)
- `scripts/`
- Store screenshots (`screenshots/`), because the metainfo links to them by URL

**Builds**
- The native build only: `meson setup build/meson && meson compile -C build/meson`
- CI: native Linux build, tests, `meson dist`

**Produces** (on each tag)
- A source tarball (`tuner-X.Y.Z.tar.xz`) and its SHA-256, attached to the GitHub Release. This is the
  single input every packaging repository consumes.

**Does not contain**
- Flatpak manifests, installer scripts, `debian/`, spec files, PKGBUILDs, web app code, mobile apps.

**Moved out of this repo** (now in `tuner-flatpak`)
- `io.github.tuner_labs.tuner.yml` (release manifest, was in the root)
- `packaging/flatpak/io.github.tuner_labs.tuner.debug.yml` (dev manifest)
- `.github/workflows/dev.yml` and `main.yml` (the Flatpak CI)

### 3.2 Flatpak packaging (the Flathub repository)

Flathub controls the Flatpak release. Its repository, `flathub/io.github.tuner_labs.tuner`, is the one
place that decides what Flathub builds and publishes, and it is hosted in Flathub's organisation, not
Tuner's. In this layout it is **the Flatpak packaging repository**: it is not replaced or duplicated, and
nothing the Tuner team does bypasses it.

**How it works today** (from <RELEASE.md>)
- Flathub builds whatever its repository's branches contain. A pull request triggers a test build;
  merging it publishes.
- Branch `main` publishes the production release. Branch `beta` publishes the beta channel for testing.
- The manifest in that repository is JSON, and names the Tuner release tag to build. Updating a release
  means opening a pull request there that changes the tag, plus any libraries, patches and documentation.
- `tuner-labs/tuner-flathub` (branch `io.github.tuner_labs.tuner`) is a **fork of `flathub/flathub`**. That
  is the repository Flathub uses for new-app submissions: an app is submitted as a pull request from a
  branch of such a fork. Once the submission was accepted, Flathub created
  `flathub/io.github.tuner_labs.tuner`, and the fork stopped having any role in releases. <RELEASE.md> also
  links a second submission fork under another maintainer's account (`louis77/flathub`), which is likewise
  historical.
- The in-tree manifests (`io.github.tuner_labs.tuner.yml` and the debug one) and the workflows that use
  them are a separate, local copy used for development and CI. They are not what Flathub builds.

**What this proposal changes**
- The Flathub repository stays authoritative for releases. Its manifest still pins a Tuner tag and
  commit, as now.
- The in-tree manifests and Flatpak workflows move out of `tuner` into a Tuner-owned working repository
  (a new `tuner-labs/tuner-flatpak`, replacing the `tuner-labs/tuner-flathub` fork). That repository holds the
  development and debug manifests, the CI, and the release manifest. All of them fetch the code with git,
  as Flathub does: Flathub builds in a sandbox that cannot see local folders, so a `type: dir` source
  would test something Flathub never does. The release manifest pins a tag and commit; the development
  manifests follow a branch, and a build script can point them at a fork, another ref, or a local clone
  (`file://`, committed work only). It must be a new repository, not a fork: GitHub cannot turn a fork into a
  standalone repository, so `tuner-labs/tuner-flathub` is deleted and the new one created (see below). Release means: update it, then open the pull request into the Flathub
  repository's `beta` or `main` branch with the same manifest.
- To avoid keeping two copies in step by hand, the working repository's release manifest is the source;
  the pull request into Flathub copies it unchanged (apart from Flathub-only files such as `flathub.json`).
- Add `x-checker-data` to the `tuner` module so Flathub's bot proposes tag bumps itself. This keeps the
  Flathub repository updated without hand-editing the tag.
- Use `beta` for pre-releases and `main` for production exactly as <RELEASE.md> describes; the migration
  does not change that process.

**Retiring the `tuner-flathub` fork**
- Deleting a fork does not affect `flathub/flathub` or `flathub/io.github.tuner_labs.tuner`.
- Before deleting, check for open pull requests from it, and for anything on its branches that is not in
  the Flathub repository or in `tuner` (patches, notes, an older manifest). Save those first.
- Update every link to it (<RELEASE.md> links it twice) when the replacement exists.

**Things to settle**
- Any patches carried in the Flathub manifest conflict with rule 1 in section 5. They should either be
  upstreamed into `tuner` or listed here as known exceptions with a reason and a plan to remove them.
- Flathub's repository, not Tuner's, decides whether a build is accepted; Flathub reviewers can require
  manifest changes. The working repository must be able to take those changes back.

### 3.3 `tuner-windows` - Windows installer

**Contains**
- `build.ps1` / MSYS2 build script
- Installer definition (Inno Setup `.iss` or WiX)
- List of GStreamer plugins and DLLs to bundle
- `source.lock` (see section 4)
- CI: Windows runner with MSYS2

**Builds** the code with `valac`, GTK3 and GStreamer from MSYS2, bundles runtime pieces (GTK, GLib,
gdk-pixbuf loaders, compiled GSettings schemas, `.mo` files, icon theme, GStreamer plugins) and produces an
installer plus a portable zip.

**Publishes** to its own GitHub Releases, then optionally winget and the Microsoft Store (MSIX).

**Needs from the code repo**: Windows support compiled in (conditional dependencies in `meson.build`,
`#if WINDOWS` for signal handling, no D-Bus/MPRIS). That is a code change and goes in `tuner`, never as a
patch here (rule 1 below).

### 3.4 `tuner-linux` - native Linux packages

One repository, one directory per format, all built from the release tarball.

**Contains**
- `debian/` (deb, optionally a PPA)
- `rpm/tuner.spec` (rpm, optionally COPR)
- `arch/PKGBUILD` (reference for the AUR)
- `appimage/` (optional)
- `nix/` (optional)
- `source.lock`
- CI: build each format in a matching container and attach the artifacts to its Releases.

Community-maintained distro packages (AUR `tuner-git`, MX Linux, Pacstall) can keep living in their own
places; this repo is the maintained reference and the place Tuner-maintained packages come from.

### 3.5 `tuner-web` - web app

A browser version of Tuner cannot be produced by compiling the Vala code, because the UI is GTK3. There are
two realistic shapes, and the repo should say which it is:

- **GTK Broadway wrapper**: a container that runs the real GTK3 Tuner on a server and shows it in a
  browser through GTK's Broadway backend. Reuses the app, but each user needs a server-side process and the
  audio plays on the server, so it suits a self-hosted or kiosk setup rather than public hosting.
- **Reimplementation (PWA)**: a new TypeScript front end that uses the Radio Browser API directly and plays
  streams with the browser's audio. Many radio streams are plain HTTP, which browsers block on HTTPS
  pages, so a small proxy may be needed.

Either way it has its own build, CI and hosting, and never shares source files with `tuner`.

### 3.6 `tuner-android` and `tuner-ios` - mobile

Native rewrites (Kotlin with Media3, Swift with AVPlayer) that use Tuner as the functional specification.
They share no source with `tuner`, so they are ordinary application repositories, not packaging
repositories.

iOS licensing: Tuner is GPL-3.0-or-later, and the GPLv3 is generally treated as incompatible with App
Store terms. Reusing Tuner code requires the copyright holders to agree to an App Store exception. A
clean-room rewrite from the specification avoids the problem. Decide this before starting.

## 4. How a packaging repository pulls in the code

Each packaging repository records exactly which version of the code it builds, in a small file that CI and
people can read:

```
# source.lock
repo    = https://github.com/tuner-labs/tuner
tag     = v2.3.0
commit  = 0123456789abcdef0123456789abcdef01234567
tarball = https://github.com/tuner-labs/tuner/releases/download/v2.3.0/tuner-2.3.0.tar.xz
sha256  = ...
```

- The build downloads the tarball, verifies the SHA-256, and builds from it. A build never uses a moving
  branch.
- The Flatpak repository has the same information in the manifest's `tuner` module instead of a separate
  file.
- For local development, a packaging repo can be pointed at a local git clone as the remote
  (`file:///path/to/tuner`), which still exercises the same fetch-with-git path. Only committed work is
  built.

**Updating to a new release**
1. Maintainers tag `vX.Y.Z` in `tuner`. CI builds and publishes the tarball and SHA-256.
2. Each packaging repository gets a pull request that updates `source.lock`. This can be automated with a
   scheduled workflow that checks the latest release, or with a `repository_dispatch` event sent by the
   release workflow in `tuner`. Flathub's bot already does this for the Flatpak manifest.
3. The packaging CI builds the new version. A maintainer merges when it passes.

## 5. Rules that keep the split workable

1. **No patches in packaging repositories.** If a package needs a code change, it is made in `tuner`
   first and arrives with the next release. Otherwise the channels slowly become different programs.
2. **Platform support is code.** Anything that needs the app itself to behave differently on a platform
   (Windows signal handling, a Windows media-controls adapter, paths, settings backend) is implemented in
   `tuner` behind a build option. Packaging only builds and wraps.
3. **One input.** Every packaging repository consumes the same release tarball, so "which version is this
   package?" always has one answer.
4. **Metadata is code.** Desktop file, metainfo, icons and schema stay in `tuner`, since they describe the
   app. Packaging repositories may add channel-specific metadata only (for example an MSIX manifest).
5. **A packaging repository can lag, but never get ahead.** It only builds tagged releases of `tuner`,
   never unreleased commits (except the explicit `dev` flavours that use a local checkout).
6. **Document the contract in the code repo.** `doc/PACKAGING.md` lists every packaging repository, its
   maintainer and which tag it currently ships.

## 6. What the code repo must provide

- A `meson dist` target that produces a complete, reproducible tarball (translations included, no build
  output).
- A release workflow that attaches the tarball and SHA-256 to the GitHub Release.
- Build options for platform differences, and the Windows support described in 3.3.
- A stable list of runtime requirements (the `dependency()` list in `meson.build`) that packagers can rely
  on, kept in `doc/DEVELOP.md`.

## 7. Migration plan

| Step | Action | Result |
|---|---|---|
| 1 | Add `meson dist` and a release workflow to `tuner` that publishes the tarball and SHA-256 | The single input exists |
| 2 | Create `tuner-labs/tuner-flatpak` (a new, non-fork repository) as the working Flatpak repository, after first saving anything of value from the `tuner-labs/tuner-flathub` fork and deleting it; move both in-tree manifests and the Flatpak workflows into it; reconcile them with the manifest in `flathub/io.github.tuner_labs.tuner` so there is one release manifest; add `x-checker-data` | `tuner` no longer carries Flatpak files; releases still go through the Flathub repository's `beta` and `main` branches |
| 3 | In `tuner`, remove the moved manifests and workflows; update `doc/DEVELOP.md` with the local-clone build workflow | Core repo is code only |
| 4 | Add Windows support to `tuner` (build options, `#if WINDOWS`, media-controls interface) | App compiles on Windows |
| 5 | Create `tuner-windows` with the MSYS2 build, bundle and installer | First non-Linux channel |
| 6 | Create `tuner-linux` with `debian/`, `rpm/`, `arch/`; adopt or hand over community packages | Native Linux channels |
| 7 | Decide the web shape (Broadway or PWA) and create `tuner-web` | Browser channel |
| 8 | Decide mobile approach and iOS licensing; create `tuner-android` / `tuner-ios` | Mobile apps |

Steps 1-3 are small and reversible and give most of the benefit. Steps 4-5 are the real engineering work.

## 8. Current state and what changes

| Today | After |
|---|---|
| `io.github.tuner_labs.tuner.yml` in the `tuner` repo root | In the Flatpak repository |
| `packaging/flatpak/io.github.tuner_labs.tuner.debug.yml` in `tuner` | In the Flatpak repository, fetching the code with git (a local clone can be the remote) |
| Flatpak CI in `tuner/.github/workflows` | In the Flatpak working repository |
| Flathub repository `flathub/io.github.tuner_labs.tuner` (`main`, `beta`) | Unchanged; still the repository Flathub builds and publishes from |
| `screenshots/` store screenshots in `tuner` (renamed from `flathub/`) | Stay in `tuner` (the metainfo links to them by URL) |
| Third-party packages (AUR, MX Linux, Pacstall) | Unchanged; `tuner-linux` becomes the maintained reference |
| `build/` for local builds | Unchanged |

## 9. Open questions

- Should a new `tuner-flatpak` be the Flatpak working repository, or should the Flathub repository be
  the only Flatpak repository, with development manifests in a folder there?
- Which patches does the Flathub manifest carry today, and can they be upstreamed?
- Which web shape is intended: Broadway wrapper or PWA?
- Who maintains each packaging repository, and who has write access to which?
- Is Microsoft Store distribution wanted for Windows?
- Is an App Store exception acceptable to all copyright holders if iOS is pursued?
