# SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
# SPDX-License-Identifier: MIT
#
# Native aarch64 OCaml toolchain matching the CardputerZero OS (Debian 13
# "trixie", glibc 2.41), used by build-device.sh.
FROM --platform=linux/arm64 debian:trixie
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ocaml-nox ocaml-dune ca-certificates \
    && rm -rf /var/lib/apt/lists/*
