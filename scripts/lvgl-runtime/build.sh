#!/bin/sh
# SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
# SPDX-License-Identifier: MIT
#
# Build the LVGL runtime that the rust-lvgl, zig-lvgl and ocaml-lvgl templates
# link against: LVGL 9.5 + cp0_lvgl + the C API in cp0_app.h.
#
#   scripts/lvgl-runtime/build.sh desktop    # this computer (SDL2 window / fbsim)
#   scripts/lvgl-runtime/build.sh device     # the CardputerZero (aarch64 Linux)
#
# Output, per target, in scripts/lvgl-runtime/out/<target>/:
#   cflags.txt  / cflags.sexp    compile flags for lvgl/lvgl.h and cp0_app.h
#   ldflags.txt / ldflags.sexp   link flags (static libraries + system libraries)
#   build/                       the SCons project (libraries, generated config)
#
# Needs the same tools as the C++ template (Python venv with SCons, SDL2 for
# desktop, the aarch64 cross compiler for device); the first device build
# downloads the device sysroot (~440 MB). Rebuilding is incremental.
set -eu

target=${1:-}
case "$target" in
desktop | device) ;;
*)
    echo "usage: $0 desktop|device" >&2
    exit 2
    ;;
esac

here=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
repo=$(CDPATH= cd -- "$here/../.." && pwd)
out="$here/out/$target"
work="$out/build"
system=$(uname -s)

if [ "$target" = device ]; then
    if [ "$system" = Linux ] && [ "$(uname -m)" = aarch64 ]; then
        profile=config_defaults.mk # building on the device itself
    else
        profile=linux_x86_cross_cp0_config_defaults.mk
    fi
    platform=device
elif [ "$system" = Darwin ]; then
    profile=darwin_config_defaults.mk
    platform=Darwin
else
    profile=linux_x86_sdl2_config_defaults.mk
    platform=Linux
fi

# A SCons project directory per target, so desktop and device builds coexist.
mkdir -p "$work"
for item in "$here/SConstruct" "$here/main" "$here"/profiles/*.mk; do
    ln -sfn "$item" "$work/$(basename "$item")"
done

# Relink and recompile the smoke program so its commands appear in the log.
rm -rf "$work/build/cp0-app-smoke" "$work/dist"

if ! command -v scons >/dev/null 2>&1; then
    echo "$0: scons not found; activate the Python environment from docs/app-development/setup.md" >&2
    exit 1
fi
jobs=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
log="$out/build.log"
echo "lvgl-runtime: building $target ($profile), log in $log"
if ! (cd "$work" && CP0_REPO_ROOT="$repo" CONFIG_DEFAULT_FILE="$profile" CONFIG_REPO_AUTOMATION=y \
    CONFIG_COMMPILE_DEBUG=1 scons -j"$jobs" >"$log" 2>&1); then
    tail -n 30 "$log" >&2
    echo "$0: build failed; full log: $log" >&2
    exit 1
fi

python3 "$here/export_flags.py" "$log" "$work" "$out" "$platform"
echo "lvgl-runtime: $target ready in $out"
