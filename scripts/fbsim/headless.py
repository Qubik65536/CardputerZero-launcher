#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
# SPDX-License-Identifier: MIT
"""Run a framebuffer app headless: scripted keys in, PNG screenshot out.

    python3 scripts/fbsim/headless.py --keys "c c c enter" --png shot.png -- ./my-app
    python3 scripts/fbsim/headless.py --keys "esc" --expect-exit 0 -- ./my-app
    python3 scripts/fbsim/headless.py --keys "2 shift+equal 3 enter" --png sum.png -- ./my-app

Key names: letters, digits, esc backspace tab enter space up down left right,
minus equal comma period slash semicolon apostrophe grave backslash
leftbracket rightbracket; "shift+<name>" holds Shift (US layout: shift+8 = *).

The same CARDPUTER_FB / CARDPUTER_FB_SIZE / CARDPUTER_INPUT contract as fbsim,
without a window: handy for CI, containers and quick checks over SSH.

Steps: start the app, wait --settle seconds, press each key in --keys (with
--delay between them), save the framebuffer to --png (taken before the last
key when that key is ESC, so quitting apps still leave a picture), then wait up
to --timeout seconds for the app to exit.
"""

import argparse
import os
import struct
import subprocess
import sys
import tempfile
import time
import zlib
from pathlib import Path

# Linux KEY_* codes for names usable in --keys.
KEY_CODES = {
    "esc": 1, "backspace": 14, "tab": 15, "enter": 28, "space": 57,
    "up": 103, "left": 105, "right": 106, "down": 108,
    **{str(digit): 1 + digit for digit in range(1, 10)}, "0": 11,
    **dict(zip("qwertyuiop", range(16, 26))),
    **dict(zip("asdfghjkl", range(30, 39))),
    **dict(zip("zxcvbnm", range(44, 51))),
    "minus": 12, "equal": 13, "leftbracket": 26, "rightbracket": 27, "semicolon": 39,
    "apostrophe": 40, "grave": 41, "backslash": 43, "comma": 51, "period": 52, "slash": 53,
}
SHIFT = 42


def key_codes(name):
    """'a' -> (code, False); 'shift+8' -> (code, True): Shift is held around the key."""
    lowered = name.lower()
    shifted = lowered.startswith("shift+")
    return KEY_CODES.get(lowered[6:] if shifted else lowered), shifted


def input_event(kind, code, value):
    now = time.time()
    seconds = int(now)
    return struct.pack("<qqHHi", seconds, int((now - seconds) * 1e6), kind, code, value)


def send(fifo, code, value):
    fifo.write(input_event(1, code, value) + input_event(0, 0, 0))
    fifo.flush()


def press(fifo, name):
    code, shifted = key_codes(name)
    if shifted:
        send(fifo, SHIFT, 1)
    send(fifo, code, 1)
    send(fifo, code, 0)
    if shifted:
        send(fifo, SHIFT, 0)


def rgb565_rows(data, width, height):
    for row in range(height):
        line = bytearray()
        for (pixel,) in struct.iter_unpack("<H", data[row * width * 2:(row + 1) * width * 2]):
            red, green, blue = (pixel >> 11) & 0x1F, (pixel >> 5) & 0x3F, pixel & 0x1F
            line += bytes(((red << 3) | (red >> 2), (green << 2) | (green >> 4), (blue << 3) | (blue >> 2)))
        yield bytes(line)


def write_png(path, data, width, height):
    raw = b"".join(b"\x00" + row for row in rgb565_rows(data, width, height))

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)  # 8-bit RGB
    Path(path).write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
                           + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--keys", default="", help="space-separated key names, e.g. 'c c enter esc' or 'shift+9'")
    parser.add_argument("--png", help="save the framebuffer here")
    parser.add_argument("--settle", type=float, default=1.0, help="seconds before the first key (default 1)")
    parser.add_argument("--delay", type=float, default=0.2, help="seconds between keys (default 0.2)")
    parser.add_argument("--timeout", type=float, default=3.0, help="seconds to wait for exit (default 3)")
    parser.add_argument("--expect-exit", type=int, help="fail unless the app exits with this status")
    parser.add_argument("--size", default="320x170", help="framebuffer size WxH (default 320x170)")
    parser.add_argument("command", nargs=argparse.REMAINDER, help="-- app [args...]")
    args = parser.parse_args(argv)
    if args.command[:1] == ["--"]:
        args.command = args.command[1:]
    if not args.command:
        parser.error("missing app command after --")
    unknown = [name for name in args.keys.split() if key_codes(name)[0] is None]
    if unknown:
        parser.error(f"unknown key names: {unknown}; known: {sorted(KEY_CODES)}")
    return args


def main(argv=None):
    args = parse_args(argv)
    width, height = (int(part) for part in args.size.split("x"))
    with tempfile.TemporaryDirectory(prefix="fbsim-") as directory:
        fb_path, input_path = os.path.join(directory, "fb"), os.path.join(directory, "input")
        Path(fb_path).write_bytes(bytes(width * height * 2))
        os.mkfifo(input_path)
        fifo_fd = os.open(input_path, os.O_RDWR)  # keeps the FIFO open for the app
        env = dict(os.environ, CARDPUTER_FB=fb_path, CARDPUTER_FB_SIZE=args.size, CARDPUTER_INPUT=input_path)
        app = subprocess.Popen(args.command, env=env)
        with os.fdopen(fifo_fd, "wb", buffering=0) as fifo:
            time.sleep(args.settle)
            names = args.keys.split()
            for index, name in enumerate(names):
                last = index == len(names) - 1
                if last and name.lower() == "esc" and args.png:
                    write_png(args.png, Path(fb_path).read_bytes(), width, height)
                press(fifo, name)
                time.sleep(args.delay)
            if args.png and not (names and names[-1].lower() == "esc"):
                write_png(args.png, Path(fb_path).read_bytes(), width, height)
            try:
                status = app.wait(timeout=args.timeout)
            except subprocess.TimeoutExpired:
                app.terminate()
                status = app.wait()
                if args.expect_exit is not None:
                    print("headless: app did not exit in time", file=sys.stderr)
                    return 1
    if args.png:
        print(f"headless: saved {args.png}")
    print(f"headless: app exit status {status}")
    if args.expect_exit is not None and status != args.expect_exit:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
