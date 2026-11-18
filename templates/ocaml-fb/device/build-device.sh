#!/bin/sh
# SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
# SPDX-License-Identifier: MIT
#
# Build the aarch64 binary for the CardputerZero: device/hello-cardputer.
#
# OCaml has no practical cross compiler from macOS, so this compiles natively
# inside an arm64 Debian trixie container (the device's OS and glibc). On Apple
# Silicon that runs natively; on x86_64 hosts Docker emulates arm64 (slower;
# needs binfmt/QEMU, which Docker Desktop and OrbStack include).
# Alternatively, build on the device itself: sudo apt install ocaml-nox ocaml-dune
set -eu
here=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
app=$(dirname "$here")
image=cardputerzero-ocaml-arm64
docker image inspect "$image" >/dev/null 2>&1 || docker build -t "$image" "$here"
docker run --rm --platform linux/arm64 --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -v "$app":/app -w /app "$image" \
    sh -c 'dune build --root . --build-dir _build_device --profile release ./src/main.exe &&
           cp -f _build_device/default/src/main.exe device/hello-cardputer'
echo "built $here/hello-cardputer"
