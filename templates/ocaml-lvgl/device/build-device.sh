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
#
# It links against the device LVGL runtime (scripts/lvgl-runtime/build.sh
# device, run on the host). Its flags hold absolute host paths (the runtime
# and the device sysroot in SDK/github_source), so the repository is mounted
# at the same path inside the container.
set -eu
here=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
app=$(dirname "$here")
repo=$(CDPATH= cd -- "$app/../.." && pwd)
image=cardputerzero-ocaml-arm64
if [ ! -f "$repo/scripts/lvgl-runtime/out/device/ldflags.txt" ]; then
    echo "hello-cardputer: the LVGL runtime for the device is not built." >&2
    echo "  Run: scripts/lvgl-runtime/build.sh device   (in $repo)" >&2
    exit 1
fi
docker image inspect "$image" >/dev/null 2>&1 || docker build -t "$image" "$here"
docker run --rm --platform linux/arm64 --user "$(id -u):$(id -g)" -e HOME=/tmp -e CP0_LVGL_TARGET=device \
    -v "$repo":"$repo" -w "$app" "$image" \
    sh -c 'dune build --root . --build-dir _build_device --profile release ./src/main.exe &&
           cp -f _build_device/default/src/main.exe device/hello-cardputer'
echo "built $here/hello-cardputer"
