#!/usr/bin/env bash

# Copyright © 2026 <https://github.com/technosf>
# SPDX-FileCopyrightText: © 2026 <https://github.com/technosf>
#
# SPDX-License-Identifier: GPL-3.0-or-later
#

#
# ImageMagic convert, rounding corners and adding drop shadow
#
# Params are release #, file name, output release#.filename 
#

convert "$2" -crop 1800x1300+0+0 \
  -resize 1250x \
  \( +clone -alpha extract \
     -draw "fill black polygon 0,0 0,40 40,0 fill white circle 40,40 40,0" \
     \( +clone -flip \) -compose Multiply -composite \
     \( +clone -flop \) -compose Multiply -composite \
  \) \
  -alpha off -compose CopyOpacity -composite \
  "Tuner.$1.$(basename "$2")"
convert "Tuner.$1.$(basename "$2")" \( +clone -background black -shadow 60x15+0+0 \) +swap -background transparent -layers merge +repage "Tuner.$1.$(basename "$2")"
#convert "Tuner.$1.$(basename "$2")" -strip -interlace Plane -gaussian-blur 0.01 -quality 85% "Tuner.$1.$(basename "$2")"
convert "Tuner.$1.$(basename "$2")" -strip -interlace Plane -quality 75% "Tuner.$1.$(basename "$2")"
optipng "Tuner.$1.$(basename "$2")"
