<!-- SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
     SPDX-License-Identifier: MIT -->
# Setting up your computer

You only need the parts for the language you use. Everything below was tested
on macOS (Apple Silicon) and Debian/Ubuntu.

## 1. The repository

```bash
git clone --recursive https://github.com/CardputerZero/launcher.git
cd launcher
# Already cloned without --recursive?
git submodule update --init --recursive
```

The `SDK` submodule holds the SCons build system and LVGL; `projects/AppStore`,
`projects/Calculator`, the CameraApp/Keyboard-Guide sources and the emulator's
LVGL copy are submodules too.

## 2. Common tools

### macOS

```bash
xcode-select --install                       # Apple clang, git, make
brew install sdl2 freetype pkg-config cmake ninja
# Cross compiler for device builds of C++ and Rust apps:
brew tap messense/macos-cross-toolchains
brew install aarch64-unknown-linux-gnu
```

Optional: Docker ([OrbStack](https://orbstack.dev) or Docker Desktop) for
`scripts/linux-sim` (Linux-only apps and test suites) and OCaml device builds.
On Apple Silicon these containers are native arm64, the same architecture as
the device.

### Debian / Ubuntu

```bash
sudo apt install build-essential pkg-config git cmake ninja-build \
    libsdl2-dev libfreetype-dev libcurl4-openssl-dev libssl-dev \
    gcc-aarch64-linux-gnu g++-aarch64-linux-gnu      # cross compiler
```

### Windows

Use WSL2 with Ubuntu and follow the Debian instructions; for GUI apps WSLg
shows the simulator windows. (The launcher itself also builds natively with
MSYS2, see the main README, but the app templates and helper scripts assume a
POSIX shell.)

## 3. Python and SCons (C++ apps and the bundled projects)

Python 3.8 or newer. A virtual environment keeps the build tools separate:

```bash
python3 -m venv ~/cardputer-venv
source ~/cardputer-venv/bin/activate          # in every new shell
pip install parse scons requests tqdm setuptools-rust paramiko scp
export CONFIG_REPO_AUTOMATION=y               # never stop builds with interactive prompts
```

The first cross (device) build of any SCons project downloads the device
sysroot (~440 MB) into `SDK/github_source/static_lib_v0.0.7/`; later builds
reuse it.

## 4. Per-language toolchains

| Language | Install | Check |
| --- | --- | --- |
| C++ | the common tools above | `scons --version` |
| Rust | [rustup](https://rustup.rs), then `rustup target add aarch64-unknown-linux-gnu` | `cargo --version` |
| Zig | **0.17.x** exactly (`brew install zig`, or a tarball from ziglang.org); Zig's standard library changes between releases | `zig version` |
| OCaml | `opam install dune` (or `brew install ocaml dune`, `apt install ocaml-nox ocaml-dune`); Docker for device builds | `dune --version` |
| Terminal apps | whatever your language needs on the device | |

## 5. The desktop simulator for framebuffer apps

```bash
scripts/fbsim/build.sh        # needs a C compiler and SDL2 -> scripts/fbsim/fbsim
```

## 6. Check everything works

```bash
python3 scripts/new_app.py rust-fb "Setup Check"         # or zig-fb / ocaml-fb / cpp-lvgl
cd projects/SetupCheck && ../../scripts/fbsim/fbsim -- cargo run
cd ../.. && rm -rf projects/SetupCheck                    # clean up afterwards
```

Or build one of the bundled projects: see [bundled projects](bundled-projects.md).

## 7. Reaching the device

The device runs SSH; the default user is `pi`. Find its IP address in
*Settings* or with your router, then `ssh pi@<device-ip>`. Over USB, enable ADB
in *Settings > Developer* (see `docs/adb-debug-guide.md`): `adb shell`,
`adb push`, and `adb forward tcp:2222 tcp:22` for SSH over USB.
