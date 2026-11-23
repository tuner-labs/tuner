#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# screenshots.sh - take representative Tuner screenshots for Flathub from a local debug build.
#
# What it does, per preset:
#   1. starts the debug build on a private virtual display (Xvfb), in a clean sandbox (throw-away
#      settings, data and cache directories, own D-Bus session), so none of your favourites, history
#      or settings show up, nothing is saved, and your real desktop, panel, other windows and mouse
#      pointer can never appear in a shot;
#   2. tells the app, through TUNER_SCREENSHOT, what to show (see src/Services/ScreenshotMode.vala);
#   3. waits for the content to settle, captures the virtual screen and crops to the window (and to a
#      popover that sticks out of it): everything that is not the empty display background;
#   4. runs scripts/process_screenshots.py over the captures (rounded corners and shadow, scaling,
#      metainfo snippet).
#
# The shots use the stock GTK Adwaita theme and icons, not your desktop theme: that is the look
# Flathub reviewers expect, and it makes the shots the same on every machine.
#
# The app side only exists in local debug builds (meson setup builddir --buildtype=debug,
# prefix other than /app), so release and Flatpak builds are not affected.
#
# Usage:
#   scripts/screenshots.sh [options] [preset ...]
#
#   -b DIR   build directory containing io.github.tuner_labs.tuner (default: builddir)
#   -o DIR   output directory (default: screenshots/shots)
#   -w SEC   seconds to wait before capturing (default: 14)
#   -p TEXT  output file prefix (default: Tuner.220.)
#   -n       capture only; skip the Flathub post-processing
#   -l       list presets and exit
#
# Presets (default: all that can run, in this order): discover trending search starred jukebox offline dark history
#
# Environment:
#   TUNER_SHOT_SIZE        window size, default 1000x625
#   TUNER_SHOT_STATION     uuid of a station to play for the shots that show a playing station
#   TUNER_SHOT_STATIONS    comma separated station uuids; each shot that shows a playing station uses the next one,
#                          so the shots do not all show the same station. Default: TUNER_SHOT_STATION followed by
#                          the TUNER_SHOT_STARRED list
#   TUNER_SHOT_INSET       pixels trimmed from each side of the window after cropping, default 5
#   TUNER_SHOT_STARRED     comma separated station uuids for the starred preset
#   TUNER_SHOT_HISTORY     comma separated station uuids played in turn (with TUNER_SHOT_HISTORY_DWELL ms each,
#                          default 15000) to fill the History list; default: the TUNER_SHOT_STARRED list
#   TUNER_SHOT_SEARCH      search text for the search preset, default "abc"
#   TUNER_SHOT_SCALE       1 (default) or 2: GDK scale of the virtual display. 2 gives sharper shots
#                          (they are scaled down to the Flathub width afterwards)
#   TUNER_SHOT_CANVAS      virtual screen size, default 1800x1300 (room for popovers); multiplied by the scale
#   TUNER_SHOT_GTK_THEME   GTK theme, default Adwaita
#   TUNER_SHOT_ICON_THEME  icon theme, default Adwaita
#   TUNER_SHOT_FONT        font, e.g. "Cantarell 11" (default: the system default)
#   TUNER_SHOT_WM          window manager to start on the virtual display, e.g. marco, openbox or metacity.
#                          Normally not needed; try it if the shots come out blank.
#   PYTHON                 command used to run process_screenshots.py, default python3. It needs Pillow:
#                          sudo apt install python3-pil   (or)   PYTHON="pipx run --spec pillow python"
#   CAPTURE_CMD            command that captures the virtual screen to the file named by its last
#                          argument; DISPLAY is already set. Default: import -window root.
#
# Needs Xvfb and ImageMagick's import:  sudo apt install xvfb imagemagick
# (Works on X11 and Wayland desktops alike: nothing is captured from the real screen.)
#
# Station names and titles come live from radio-browser.info: look at every shot before it is
# published (no rude names, no personal data).

set -u

BUILD=builddir
OUT=screenshots/shots
WAIT=14
PREFIX=Tuner.220.
POST=1
SIZE=${TUNER_SHOT_SIZE:-1000x625}
STATION=${TUNER_SHOT_STATION:-}
STATIONS=${TUNER_SHOT_STATIONS:-}   # stations to rotate through, one per shot that shows a playing station
INSET=${TUNER_SHOT_INSET:-5}        # pixels trimmed from every side of the window (its outline)
STARRED=${TUNER_SHOT_STARRED:-}
SEARCH=${TUNER_SHOT_SEARCH:-abc}
SCALE=${TUNER_SHOT_SCALE:-1}
CANVAS=${TUNER_SHOT_CANVAS:-1800x1300}
GTK_THEME_NAME=${TUNER_SHOT_GTK_THEME:-Adwaita}
ICON_THEME_NAME=${TUNER_SHOT_ICON_THEME:-Adwaita}
FONT_NAME=${TUNER_SHOT_FONT:-}
HISTORY_LIST=${TUNER_SHOT_HISTORY:-}     # stations played in turn for the history shot; default: the starred list
HISTORY_DWELL_MS=${TUNER_SHOT_HISTORY_DWELL:-15000}
APP_ID=io.github.tuner_labs.tuner
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(dirname "$HERE")

ALL_PRESETS="discover trending search starred jukebox offline dark history"   # history last: it needs the longest run and the most content

spec_for() {
    local base="size=$SIZE;theme=light"
    local playing=""
    [ -n "$STATION" ] && playing=";station=$STATION"
    case "$1" in
        discover) echo "$base;view=Discover$playing" ;;
        trending) echo "$base;view=Trending$playing" ;;
        search)   echo "$base;view=Discover$playing;search=$SEARCH" ;;
        starred)  [ -n "$STARRED" ] || return 1
                  echo "$base;starred=$STARRED;view=Starred by You$playing;popover=preferences" ;;
        history)  [ -n "$STATION" ] || return 1
                  echo "$base;view=Discover;history=${HISTORY_LIST:-$STARRED};history_dwell=$HISTORY_DWELL_MS;station=$STATION;popover=history;popover_delay=1000" ;;
        jukebox)  echo "$base;view=Discover;activate=Jukebox;activate_wait=12000" ;;
        offline)  echo "$base;offline=1" ;;
        dark)     echo "size=$SIZE;theme=dark;view=Discover$playing" ;;
        *)        return 2 ;;
    esac
}

capture_screen() {   # capture_screen FILE - the whole virtual screen (DISPLAY is the virtual one)
    if [ -n "${CAPTURE_CMD:-}" ]; then
        $CAPTURE_CMD "$1"
    elif command -v import >/dev/null; then
        import -window root "$1"
    else
        echo "  No capture tool found (sudo apt install imagemagick, or set CAPTURE_CMD)"
        return 1
    fi
}

window_ready() {   # window_ready - true when a big window is mapped on the virtual display
    DISPLAY=":$DISP_NUM" xwininfo -root -tree 2>/dev/null | awk '
        /[0-9]+x[0-9]+\+[0-9-]+\+[0-9-]+/ {
            for (i = 1; i <= NF; i++)
                if ($i ~ /^[0-9]+x[0-9]+\+/) { split($i, g, /[x+]/); if (g[1] >= 300 && g[2] >= 200) ok = 1 }
        }
        END { exit ok ? 0 : 1 }'
}

free_display() {   # free_display - print an unused X display number
    local n
    for n in $(seq 90 130); do
        if [ ! -e "/tmp/.X11-unix/X$n" ] && [ ! -e "/tmp/.X$n-lock" ]; then echo "$n"; return 0; fi
    done
    return 1
}

while getopts "b:o:w:p:nl" opt; do
    case $opt in
        b) BUILD=$OPTARG ;;
        o) OUT=$OPTARG ;;
        w) WAIT=$OPTARG ;;
        p) PREFIX=$OPTARG ;;
        n) POST=0 ;;
        l) echo "$ALL_PRESETS"; exit 0 ;;
        *) sed -n '2,45p' "$0"; exit 2 ;;
    esac
done
shift $((OPTIND - 1))
PRESETS=${*:-$ALL_PRESETS}

BIN="$BUILD/$APP_ID"
[ -x "$BIN" ] || { echo "No $BIN. Build first: meson compile -C $BUILD (local debug build)"; exit 1; }
command -v Xvfb >/dev/null || { echo "Xvfb is needed for a clean virtual display: sudo apt install xvfb"; exit 1; }
case "$SCALE" in 1|2) ;; *) echo "TUNER_SHOT_SCALE must be 1 or 2"; exit 1 ;; esac
case "$CANVAS" in *x*) ;; *) echo "TUNER_SHOT_CANVAS must look like 1800x1300"; exit 1 ;; esac
if command -v strings >/dev/null && ! strings "$BIN" | grep -q TUNER_SCREENSHOT; then
    echo "$BIN has no screenshot mode: it must be a local debug build (meson setup --buildtype=debug, prefix not /app)."
    exit 1
fi

RAW="$OUT/raw"
mkdir -p "$RAW"
SCHEMA_DIR=$(cd "$BUILD/data" && pwd)
captured=()

# Virtual display shared by all presets; the app is restarted for each one
CANVAS_W=$(( ${CANVAS%x*} * SCALE )); CANVAS_H=$(( ${CANVAS#*x} * SCALE ))
DISP_NUM=$(free_display) || { echo "No free X display number between :90 and :130"; exit 1; }
XVFB_LOG=$(mktemp)
Xvfb ":$DISP_NUM" -screen 0 "${CANVAS_W}x${CANVAS_H}x24" -nolisten tcp >"$XVFB_LOG" 2>&1 &
XVFB_PID=$!
cleanup() { [ -n "$WM_PID" ] && kill "$WM_PID" 2>/dev/null; kill "$XVFB_PID" 2>/dev/null; }
trap cleanup EXIT
for _ in $(seq 1 50); do
    [ -e "/tmp/.X11-unix/X$DISP_NUM" ] && break
    kill -0 "$XVFB_PID" 2>/dev/null || { echo "Xvfb failed to start:"; sed 's/^/    /' "$XVFB_LOG"; exit 1; }
    sleep 0.1
done
WM_PID=""
if [ -n "${TUNER_SHOT_WM:-}" ]; then
    DISPLAY=":$DISP_NUM" ${TUNER_SHOT_WM} >"$XVFB_LOG.wm" 2>&1 &
    WM_PID=$!
    sleep 1
fi
echo "[xvfb] display :$DISP_NUM ${CANVAS_W}x${CANVAS_H}, scale $SCALE, theme $GTK_THEME_NAME / $ICON_THEME_NAME"

# Rotation of playing stations: TUNER_SHOT_STATIONS, else the single station then the starred ones
pool=()
IFS=',' read -r -a _pool_in <<< "${STATIONS:-${STATION:+$STATION,}$STARRED}"
for _uuid in "${_pool_in[@]}"; do
    _uuid=${_uuid// /}
    [ -n "$_uuid" ] || continue
    _dup=0
    for _seen in "${pool[@]:-}"; do [ "$_seen" = "$_uuid" ] && _dup=1; done
    [ "$_dup" -eq 0 ] && pool+=("$_uuid")
done
pool_index=0

for preset in $PRESETS; do
    case "$preset" in
        jukebox|offline) ;;    # these show no playing station
        *)  if [ ${#pool[@]} -gt 0 ]; then
                STATION=${pool[$((pool_index % ${#pool[@]}))]}
                pool_index=$((pool_index + 1))
            fi ;;
    esac
    spec=$(spec_for "$preset"); rc=$?
    if [ $rc -eq 1 ]; then
        echo "[skip] $preset: needs TUNER_SHOT_STARRED (starred) or TUNER_SHOT_STATION (history)"
        continue
    elif [ $rc -ne 0 ]; then
        echo "[skip] $preset: unknown preset (try -l)"
        continue
    fi

    sandbox=$(mktemp -d)
    file="$RAW/$preset.png"
    echo "[run ] $preset: $spec"

    wait_s=$WAIT
    [ "$preset" = jukebox ] && wait_s=$((WAIT + 12))    # activate_wait in the spec
    if [ "$preset" = history ]; then
        list=${HISTORY_LIST:-$STARRED}
        count=$(echo "$list" | tr ',' '\n' | grep -c .)
        wait_s=$((WAIT + 10 + count * (HISTORY_DWELL_MS / 1000 + 4)))
    fi

    # Dark preset: GTK_THEME overrides the app's own dark-mode request, so ask for the dark variant here
    gtk_theme=$GTK_THEME_NAME
    case "$spec" in *theme=dark*) gtk_theme="$GTK_THEME_NAME:dark" ;; esac

    # Stock look: GTK reads these from settings.ini because no desktop settings daemon runs here
    mkdir -p "$sandbox/config/gtk-3.0"
    {
        echo "[Settings]"
        echo "gtk-theme-name=$GTK_THEME_NAME"
        echo "gtk-icon-theme-name=$ICON_THEME_NAME"
        [ -n "$FONT_NAME" ] && echo "gtk-font-name=$FONT_NAME"
        echo "gtk-enable-animations=false"
    } >"$sandbox/config/gtk-3.0/settings.ini"

    # Own session bus + throw-away settings/data/cache: nothing real is shown or saved.
    runner=(env
        -u WAYLAND_DISPLAY -u XAUTHORITY
        DISPLAY=":$DISP_NUM" GDK_BACKEND=x11 GDK_SCALE="$SCALE" GDK_DPI_SCALE=1
        GTK_THEME="$gtk_theme" GTK_A11Y=none NO_AT_BRIDGE=1
        GTK_USE_PORTAL=0 GIO_USE_PORTAL=0
        LANG=C.UTF-8 LANGUAGE=en
        GSETTINGS_BACKEND=memory GSETTINGS_SCHEMA_DIR="$SCHEMA_DIR"
        XDG_DATA_HOME="$sandbox/data" XDG_CONFIG_HOME="$sandbox/config" XDG_CACHE_HOME="$sandbox/cache"
        TUNER_SCREENSHOT="$spec"
        "$BIN")
    if command -v dbus-run-session >/dev/null; then
        setsid dbus-run-session -- "${runner[@]}" >"$sandbox/log.txt" 2>&1 &
    else
        setsid "${runner[@]}" >"$sandbox/log.txt" 2>&1 &
    fi
    pgid=$!

    # Wait (up to 60 s) for the window to be shown at its real size, then let the content load
    if command -v xwininfo >/dev/null; then
        deadline=$((SECONDS + 60))
        until window_ready || [ "$SECONDS" -ge "$deadline" ]; do sleep 1; done
        window_ready || echo "[WARN] $preset: no window of a usable size after 60 s; capturing anyway"
    fi
    sleep "$wait_s"
    if ! kill -0 "$pgid" 2>/dev/null; then
        echo "[FAIL] $preset: the app exited. App log: $sandbox/log.txt"
        tail -n 15 "$sandbox/log.txt" | sed 's/^/        /'
        continue
    fi

    DISPLAY=":$DISP_NUM" capture_screen "$file"
    if command -v identify >/dev/null && [ -s "$file" ] \
       && [ "$(identify -format %k "$file" 2>/dev/null)" = "1" ]; then
        echo "[WARN] $preset: the capture is one flat colour, so the window was not drawn."
        echo "        Windows on the virtual display:"
        DISPLAY=":$DISP_NUM" xwininfo -root -tree 2>&1 | sed 's/^/          /' | head -12
        echo "        App log (kept in $RAW/$preset.log):"
        tail -n 20 "$sandbox/log.txt" | sed 's/^/          /'
    fi
    cp "$sandbox/log.txt" "$RAW/$preset.log" 2>/dev/null
    kill -TERM -- "-$pgid" 2>/dev/null
    sleep 1
    kill -KILL -- "-$pgid" 2>/dev/null

    if [ -s "$file" ]; then
        captured+=("$file")
        echo "[ ok ] $file"
    else
        echo "[FAIL] $preset: no capture. App log: $sandbox/log.txt"
    fi
done

[ ${#captured[@]} -gt 0 ] || { echo "Nothing captured."; exit 1; }

if [ "$POST" -eq 1 ]; then
    captions="$ROOT/screenshots/captions.txt"
    cap_args=()
    [ -f "$captions" ] && cap_args=(--captions "$captions")
    # shellcheck disable=SC2086   # PYTHON may be a multi-word command
    ${PYTHON:-python3} "$HERE/process_screenshots.py" --add-shadow --crop bg --inset "$INSET" --prefix "$PREFIX" "${cap_args[@]}" \
        -o "$OUT/ready" "${captured[@]}"
fi
