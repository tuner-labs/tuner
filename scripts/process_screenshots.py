#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""
process_screenshots.py - check and prepare Tuner screenshots for the store listing (Flathub, AppStream).

Takes the raw window captures (PNG) and produces files ready to publish, then
prints the AppStream <screenshots> block for the metainfo file.

Rules applied (from Flathub reviewer guidance; the official quality-guidelines
page could not be fetched, so every limit is a command-line option):

  * Capture ONE window, not the screen, with the GNOME screenshot tool's window
    mode. That gives rounded corners and a transparent drop shadow.
    "Don't edit that further" - so the shadow and corners are never touched
    unless you pass --add-shadow for a capture that has none.
  * Transparent background (RGBA, transparent corners). A capture with opaque
    corners has no shadow; it is reported as a FAIL.
  * Landscape. Portrait or near-square captures are reported.
  * About 700-1200 px wide. Larger images are scaled down; smaller ones are
    reported (re-capture at a higher display scale instead of upscaling).
  * Not fullscreen: leave room around the window.
  * GNOME apps show only the close button (check by eye - not testable here).

Usage:
    process_screenshots.py [options] IN.png [IN.png ...]

    -o DIR            output directory (default: ./screenshots-ready)
    --max-width N     scale down anything wider than N px (default 1000)
    --min-width N     warn below N px (default 700)
    --add-shadow      draw rounded corners and a drop shadow on captures
                      that have none (opaque corners)
    --base-url URL    base URL used in the metainfo snippet
    --captions FILE   text file, one "filename.png = Caption" per line
    --check           only report, write nothing
    --crop bg         the capture is of a virtual display: crop to everything that is not
                      the plain background (its most common colour). This is
                      what scripts/screenshots.sh uses.
    --crop auto       the capture is a whole desktop with the app window in its
                      top-left corner: find the window's right and bottom edges and
                      crop to them. Needs a clear edge against the background.
    --crop X,Y,W,H    crop every image to this rectangle (original pixels)
    --rect NAME=X,Y,W,H
                      crop one image (by file name) to its own rectangle; repeatable,
                      wins over --crop. Use it for popovers that stick out of the window.
    --shadow-radius N, --shadow-offset N, --shadow-opacity N (0-255), --corner-radius N
                      look of the shadow and rounded corners added by --add-shadow
                      (defaults 30, 0, 255, 15)
    --inset N         with --crop bg: trim N px from every side (the window's 1 px outline)
    --prefix TEXT     prepend TEXT to every output file name (e.g. Tuner.220.)

Exit status: 0 if every image passed, 1 if any FAIL, 2 on usage error.
Needs Pillow: sudo apt install python3-pil, or run it as: pipx run --spec pillow python process_screenshots.py ...
"""

import argparse
import os
import sys

try:
    from PIL import Image, ImageChops, ImageDraw, ImageFilter
except ImportError:
    sys.exit("Pillow is required: sudo apt install python3-pil  (or run: pipx run --spec pillow python process_screenshots.py ...)")

DEFAULT_BASE_URL = "https://raw.githubusercontent.com/tuner-labs/tuner/main/screenshots"
CORNER_PROBE = 3          # px in from each corner to probe for transparency
SHADOW_RADIUS = 30
SHADOW_OFFSET_Y = 0
SHADOW_OPACITY = 255      # 0-255
WINDOW_RADIUS = 15
MARGIN = SHADOW_RADIUS * 2 + SHADOW_OFFSET_Y


class Report:
    def __init__(self, name):
        self.name = name
        self.fails = []
        self.warns = []
        self.notes = []

    def fail(self, msg):
        self.fails.append(msg)

    def warn(self, msg):
        self.warns.append(msg)

    def note(self, msg):
        self.notes.append(msg)

    def print(self):
        status = "FAIL" if self.fails else ("WARN" if self.warns else "ok")
        print(f"[{status:4}] {self.name}")
        for m in self.fails:
            print(f"         FAIL: {m}")
        for m in self.warns:
            print(f"         warn: {m}")
        for m in self.notes:
            print(f"         {m}")


def _pixels(img):
    """Pixel values of a single-band image as a list (getdata is deprecated in newer Pillow)."""
    return list(img.get_flattened_data() if hasattr(img, "get_flattened_data") else img.getdata())


def _strongest_edge(img, axis, lo, hi, band):
    """Position (1-based) of the strongest brightness step along `axis` in [lo, hi).

    axis 0 finds a vertical edge (x); axis 1 finds a horizontal edge (y).
    `band` is the (start, end) range on the other axis to average over.
    """
    g = img.convert("L")
    w, h = g.size
    if axis == 0:
        strip = g.crop((0, band[0], w, band[1]))
        diff = ImageChops.difference(strip.crop((0, 0, w - 1, strip.height)),
                                     strip.crop((1, 0, w, strip.height)))
        profile = _pixels(diff.resize((w - 1, 1), Image.BOX))
    else:
        strip = g.crop((band[0], 0, band[1], h))
        diff = ImageChops.difference(strip.crop((0, 0, strip.width, h - 1)),
                                     strip.crop((0, 1, strip.width, h)))
        profile = _pixels(diff.resize((1, h - 1), Image.BOX))
    best = max(range(lo, min(hi, len(profile))), key=lambda i: profile[i])
    return best + 1


def auto_window_rect(img):
    """Rectangle (0, 0, w, h) of an app window sitting in the top-left of a desktop capture."""
    w, h = img.size
    right = _strongest_edge(img, 0, int(w * 0.40), int(w * 0.85), (int(h * 0.08), int(h * 0.57)))
    bottom = _strongest_edge(img, 1, int(h * 0.45), int(h * 0.90), (int(w * 0.10), int(w * 0.48)))
    return (0, 0, right, bottom)


def background_rect(img):
    """Bounding box of everything that is not the plain background of the capture.

    The background colour is the most common colour of the capture. Meant for captures of a
    virtual display where the app window (and any popover) sits on a much larger empty root window.
    """
    rgb = img.convert("RGB")
    key = max(rgb.resize((64, 64), Image.NEAREST).getcolors(4096))[1]
    return ImageChops.difference(rgb, Image.new("RGB", rgb.size, key)).getbbox()


def parse_rect(text):
    parts = [int(v) for v in text.split(",")]
    if len(parts) != 4:
        raise ValueError(f"expected X,Y,W,H, got '{text}'")
    x, y, w, h = parts
    return (x, y, x + w, y + h)


def has_transparent_corners(img):
    """True if all four corners are fully or mostly transparent."""
    if img.mode != "RGBA":
        return False
    w, h = img.size
    px = img.load()
    points = [(CORNER_PROBE, CORNER_PROBE), (w - 1 - CORNER_PROBE, CORNER_PROBE),
              (CORNER_PROBE, h - 1 - CORNER_PROBE), (w - 1 - CORNER_PROBE, h - 1 - CORNER_PROBE)]
    return all(px[p][3] < 200 for p in points)


def add_shadow(img, radius=SHADOW_RADIUS, offset_y=SHADOW_OFFSET_Y, opacity=SHADOW_OPACITY,
               corner=WINDOW_RADIUS):
    """Round the corners of an opaque window capture and add a drop shadow.

    radius: blur size of the shadow in px; offset_y: how far it is shifted down;
    opacity: 0-255 darkness at its strongest; corner: window corner radius in px.
    """
    img = img.convert("RGBA")
    w, h = img.size
    margin = radius * 2 + offset_y

    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, w - 1, h - 1), corner, fill=255)
    rounded = img.copy()
    rounded.putalpha(mask)

    canvas = Image.new("RGBA", (w + 2 * margin, h + 2 * margin), (0, 0, 0, 0))

    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow_alpha = Image.new("L", canvas.size, 0)
    shadow_alpha.paste(mask.point(lambda v: opacity if v else 0), (margin, margin + offset_y))
    shadow_alpha = shadow_alpha.filter(ImageFilter.GaussianBlur(radius / 2))
    shadow.putalpha(shadow_alpha)

    canvas.alpha_composite(shadow)
    canvas.alpha_composite(rounded, (margin, margin))
    return canvas


def process(path, args, out_dir):
    name = os.path.basename(path)
    rep = Report(name)
    try:
        img = Image.open(path)
        img.load()
    except Exception as exc:                      # unreadable / not an image
        rep.fail(f"cannot open: {exc}")
        return rep, None

    if img.format != "PNG":
        rep.warn(f"format is {img.format}; Flathub screenshots should be PNG")

    # Crop to the window
    box = args.rects.get(name)
    if box is None and args.crop == "bg":
        box = background_rect(img)
        if box is None:
            rep.fail("the capture is empty: nothing differs from the background")
            return rep, None
        n = args.inset
        if n > 0 and box[2] - box[0] > 2 * n + 10 and box[3] - box[1] > 2 * n + 10:
            box = (box[0] + n, box[1] + n, box[2] - n, box[3] - n)
    elif box is None and args.crop == "auto":
        box = auto_window_rect(img)
    elif box is None and args.crop:
        box = parse_rect(args.crop)
    if box is not None:
        img = img.crop(box)
        rep.note(f"cropped to window {box[2] - box[0]}x{box[3] - box[1]} at ({box[0]},{box[1]})")

    # Transparency / shadow
    if img.mode != "RGBA":
        img = img.convert("RGBA")
        opaque = True
    else:
        opaque = not has_transparent_corners(img)

    if opaque:
        if args.add_shadow:
            img = add_shadow(img, args.shadow_radius, args.shadow_offset, args.shadow_opacity, args.corner_radius)
            rep.note("no transparent corners: added rounded corners and drop shadow")
        else:
            rep.fail("corners are opaque, so the capture has no window shadow/rounded corners. "
                     "Re-capture one window with the GNOME screenshot tool (window mode), "
                     "or pass --add-shadow")

    w, h = img.size

    # Orientation
    if h > w:
        rep.fail(f"portrait ({w}x{h}); Flathub prefers landscape")
    elif w / h < 1.2:
        rep.warn(f"nearly square ({w}x{h}); a landscape window looks better in the listing")

    # Size
    if w > args.max_width:
        scale = args.max_width / w
        img = img.resize((args.max_width, round(h * scale)), Image.LANCZOS)
        rep.note(f"scaled {w}x{h} -> {img.size[0]}x{img.size[1]}")
    elif w < args.min_width:
        rep.warn(f"only {w}px wide (want {args.min_width}+). Re-capture at 150-200% display "
                 f"scale rather than upscaling")

    result = None
    if not args.check and not rep.fails:
        os.makedirs(out_dir, exist_ok=True)
        out = os.path.join(out_dir, args.prefix + os.path.splitext(name)[0] + ".png")
        img.save(out, "PNG", optimize=True)          # re-saved without metadata
        result = out
        rep.note(f"wrote {out} ({os.path.getsize(out) // 1024} KiB)")
    return rep, result


def read_captions(path):
    caps = {}
    if not path:
        return caps
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, _, val = line.partition("=")
                caps[key.strip()] = val.strip()
    return caps


def xml_escape(text):
    return (text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


def metainfo_snippet(files, base_url, captions, prefix=""):
    lines = ["  <screenshots>"]
    for i, f in enumerate(files):
        base = os.path.basename(f)
        stem = os.path.splitext(base)[0]
        bare = stem[len(prefix):] if prefix and stem.startswith(prefix) else stem
        caption = captions.get(base) or captions.get(stem) or captions.get(bare) \
            or captions.get(bare + ".png") or bare.replace("_", " ").replace("-", " ")
        attr = ' type="default"' if i == 0 else ""
        lines.append(f"    <screenshot{attr}>")
        lines.append(f"      <image>{base_url.rstrip('/')}/{base}</image>")
        lines.append(f"      <caption>{xml_escape(caption)}</caption>")
        lines.append("    </screenshot>")
    lines.append("  </screenshots>")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description="Check and prepare screenshots for Flathub.")
    ap.add_argument("images", nargs="+", help="PNG window captures")
    ap.add_argument("-o", "--out", default="screenshots-ready")
    ap.add_argument("--max-width", type=int, default=1000)
    ap.add_argument("--min-width", type=int, default=700)
    ap.add_argument("--add-shadow", action="store_true")
    ap.add_argument("--base-url", default=DEFAULT_BASE_URL)
    ap.add_argument("--captions")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--crop", help="'bg', 'auto' or X,Y,W,H")
    ap.add_argument("--rect", action="append", default=[], help="NAME=X,Y,W,H")
    ap.add_argument("--prefix", default="")
    ap.add_argument("--shadow-radius", type=int, default=SHADOW_RADIUS, help="shadow blur size in px (default %(default)s)")
    ap.add_argument("--shadow-offset", type=int, default=SHADOW_OFFSET_Y, help="shadow shift downwards in px (default %(default)s)")
    ap.add_argument("--shadow-opacity", type=int, default=SHADOW_OPACITY, help="shadow darkness 0-255 (default %(default)s)")
    ap.add_argument("--corner-radius", type=int, default=WINDOW_RADIUS, help="window corner radius in px (default %(default)s)")
    ap.add_argument("--inset", type=int, default=0, help="with --crop bg: trim N px from every side")
    args = ap.parse_args()

    args.rects = {}
    for item in args.rect:
        key, _, val = item.partition("=")
        try:
            args.rects[key.strip()] = parse_rect(val)
        except ValueError as exc:
            ap.error(f"--rect {item}: {exc}")

    captions = read_captions(args.captions)
    written, failed = [], False
    for path in args.images:
        rep, out = process(path, args, args.out)
        rep.print()
        failed = failed or bool(rep.fails)
        if out:
            written.append(out)

    if written:
        print("\nMetainfo snippet (first image is the default screenshot):\n")
        print(metainfo_snippet(written, args.base_url, captions, args.prefix))
        print("\nChecked by eye, not by this script: only a close button in the title bar; "
              "window not fullscreen; sample content is clean (no rude station names, no personal data).")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
