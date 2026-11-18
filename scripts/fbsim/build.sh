#!/bin/sh
# SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
# SPDX-License-Identifier: MIT
#
# Build the fbsim desktop framebuffer/keyboard simulator next to this script.
# Needs a C compiler and SDL2 development files (brew install sdl2 pkg-config,
# or apt install libsdl2-dev pkg-config).
set -eu
here=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
${CC:-cc} -O2 -Wall -Wextra "$here/fbsim.c" $(pkg-config --cflags --libs sdl2) -o "$here/fbsim"
echo "built $here/fbsim"
