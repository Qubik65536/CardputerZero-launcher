# SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
# SPDX-License-Identifier: MIT
#
# Linux development image for CardputerZero projects.
#
# - Builds every SCons project with its linux_x86_sdl2 profile (the profile
#   name is historical: it also works on arm64 hosts such as Apple Silicon).
# - Runs SDL simulators headless under Xvfb and exposes them over VNC.
# - Runs the Linux-only test suites (APPLaunch, cp0_lvgl, ZClaw, LaunchWizard).
#
# Used by scripts/linux-sim/linux-sim.sh; see docs/app-development/ for usage.
FROM debian:trixie

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential g++ make cmake ninja-build pkg-config git ca-certificates file rsync procps \
        python3 python3-pip python3-venv \
        libsdl2-dev libsdl2-image-dev libfreetype-dev libcurl4-openssl-dev libssl-dev libffi-dev \
        libinput-dev libxkbcommon-dev libudev-dev nlohmann-json3-dev \
        xvfb xauth x11vnc x11-apps x11-utils imagemagick \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --break-system-packages parse scons requests tqdm

# Unprivileged user: several test suites assert on permission errors.
RUN useradd --create-home --uid 1000 dev && mkdir -p /work && chown dev:dev /work
USER dev
WORKDIR /work
