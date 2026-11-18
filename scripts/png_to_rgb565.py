#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
# SPDX-License-Identifier: MIT
"""Convert a PNG into raw RGB565 pixels for framebuffer apps.

    python3 scripts/png_to_rgb565.py sprite.png assets/sprite.rgb565

Output layout (all little-endian), easy to embed with include_bytes! /
@embedFile / a file read:

    u16 width, u16 height,
    width*height u16 RGB565 pixels (row by row),
    width*height u8 alpha values   (only with --alpha; 0 = transparent)

Supports non-interlaced 8-bit grayscale, gray+alpha, RGB, RGBA and palette
PNGs. Standard library only.
"""

import argparse
import struct
import sys
import zlib
from pathlib import Path

CHANNELS = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}  # PNG color type -> samples per pixel


def read_chunks(data):
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        sys.exit("png_to_rgb565: not a PNG file")
    offset = 8
    while offset < len(data):
        length, kind = struct.unpack(">I4s", data[offset:offset + 8])
        yield kind, data[offset + 8:offset + 8 + length]
        offset += 12 + length


def paeth(left, up, up_left):
    estimate = left + up - up_left
    distances = (abs(estimate - left), abs(estimate - up), abs(estimate - up_left))
    return (left, up, up_left)[distances.index(min(distances))]


def unfilter(raw, width, height, bpp):
    stride = width * bpp
    rows, previous, position = [], bytearray(stride), 0
    for _ in range(height):
        kind, line = raw[position], bytearray(raw[position + 1:position + 1 + stride])
        position += 1 + stride
        for i in range(stride):
            left = line[i - bpp] if i >= bpp else 0
            up = previous[i]
            up_left = previous[i - bpp] if i >= bpp else 0
            predictor = (0, left, up, (left + up) // 2, paeth(left, up, up_left))[kind]
            line[i] = (line[i] + predictor) & 0xFF
        rows.append(line)
        previous = line
    return rows


def decode(path):
    header, palette, alpha_table, idat = None, None, None, b""
    for kind, body in read_chunks(Path(path).read_bytes()):
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"PLTE":
            palette = [tuple(body[i:i + 3]) for i in range(0, len(body), 3)]
        elif kind == b"tRNS":
            alpha_table = body
        elif kind == b"IDAT":
            idat += body
    width, height, depth, color_type, _, _, interlace = header
    if depth != 8 or interlace or color_type not in CHANNELS:
        sys.exit("png_to_rgb565: only 8-bit, non-interlaced PNGs are supported")
    channels = CHANNELS[color_type]
    rows = unfilter(zlib.decompress(idat), width, height, channels)
    pixels = []
    for row in rows:
        for x in range(width):
            sample = row[x * channels:(x + 1) * channels]
            if color_type == 0:
                pixels.append((sample[0],) * 3 + (255,))
            elif color_type == 4:
                pixels.append((sample[0],) * 3 + (sample[1],))
            elif color_type == 2:
                pixels.append(tuple(sample) + (255,))
            elif color_type == 6:
                pixels.append(tuple(sample))
            else:
                index = sample[0]
                alpha = alpha_table[index] if alpha_table and index < len(alpha_table) else 255
                pixels.append(palette[index] + (alpha,))
    return width, height, pixels


def parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("png", help="input PNG")
    parser.add_argument("output", help="output .rgb565 file")
    parser.add_argument("--alpha", action="store_true", help="append an 8-bit alpha mask")
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    width, height, pixels = decode(args.png)
    if width > 0xFFFF or height > 0xFFFF:
        sys.exit("png_to_rgb565: image too large")
    out = bytearray(struct.pack("<HH", width, height))
    for red, green, blue, _ in pixels:
        out += struct.pack("<H", ((red & 0xF8) << 8) | ((green & 0xFC) << 3) | (blue >> 3))
    if args.alpha:
        out += bytes(pixel[3] for pixel in pixels)
    Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    Path(args.output).write_bytes(out)
    print(f"png_to_rgb565: {args.output} ({width}x{height}{', with alpha' if args.alpha else ''})")


if __name__ == "__main__":
    main()
