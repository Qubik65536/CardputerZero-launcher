<!-- SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
     SPDX-License-Identifier: MIT -->
# Building and running the bundled projects

Every project in `projects/` builds for the device and runs as a simulator on
your computer. This is a good first check of your [setup](setup.md), and the
projects are useful references. Run SCons commands **inside the project
directory**, with the Python virtual environment active and
`CONFIG_REPO_AUTOMATION=y` exported.

## Status at a glance

| Project | Simulator on macOS | Simulator on Linux | Device build from macOS | Device build from Linux |
| --- | --- | --- | --- | --- |
| HelloWorld | ✅ `scons` | ✅ `scons` | ✅ mac_cross | ✅ linux_x86_cross |
| UserDemo | ✅ `scons` | ✅ `scons` | ✅ linux_x86_cross | ✅ linux_x86_cross |
| APPLaunch (the launcher) | ✅ `scons` | ✅ `scons` | ✅ mac_cross | ✅ linux_x86_cross |
| ZClaw | ⚠️ builds, window stays black: use linux-sim | ✅ `scons` | ✅ mac_cross | ✅ linux_x86_cross |
| LaunchWizard | ➡️ Linux-only: use linux-sim | ✅ `scons` | ✅ `scons` (default) | ✅ linux_x86_cross |
| Calculator (submodule) | ✅ with env overrides | ✅ `scons` | ✅ with env overrides | ✅ linux_x86_cross |
| AppStore (submodule) | ➡️ use linux-sim | ✅ `scons` | ✅ with env overrides | ✅ linux_x86_cross |
| CameraApp | ✅ CMake `darwin-arm64` preset | ✅ CMake `linux-x86-64` | ❌ needs libcamera ≥ 0.7.2 sysroot | ❌ same |
| Keyboard-Guide (submodule) | ✅ CMake | ✅ CMake | ✅ CMake toolchain file | ✅ same |
| CardputerZero-Emulator | ✅ CMake | ✅ CMake | n/a (desktop tool) | n/a |

## SCons projects (HelloWorld, UserDemo, APPLaunch, ZClaw, LaunchWizard)

```bash
cd projects/HelloWorld
scons -j8                      # macOS -> darwin_config_defaults.mk, Linux x86_64 -> linux_x86_sdl2
cd dist && ./HelloWorld        # binary names: HelloWorld, M5CardputerZero-UserDemo,
                               # M5CardputerZero-APPLaunch, ZClaw, LaunchWizard
```

Device build (`file dist/<binary>` should say `ARM aarch64`):

```bash
CONFIG_DEFAULT_FILE=mac_cross_cp0_config_defaults.mk scons -j8          # from macOS
CONFIG_DEFAULT_FILE=linux_x86_cross_cp0_config_defaults.mk scons -j8    # from Linux (also works on macOS)
```

On macOS the projects find the Homebrew cross compiler through
`scripts/scons/cp0_host_toolchain.py`. Switching profiles regenerates the
configuration automatically; if a build ever looks stale, run `scons distclean`.
`linux_x86_sdl2` also works on arm64 Linux despite its name.

Closing a simulator window (or Ctrl-C) shuts the app down cleanly.

## Calculator and AppStore (submodules)

Their build files live in other repositories, so on macOS pass the toolchain
settings as environment variables (environment values override profiles):

```bash
cd projects/Calculator
# simulator (macOS)
CONFIG_DEFAULT_FILE=linux_x86_sdl2_config_defaults.mk CONFIG_TOOLCHAIN_FLAGS=-std=gnu++17 scons -j8
cd dist && ./Calculator
# device build (macOS); AppStore uses linux_x86_cross_cp0_config_defaults.mk
scons distclean
CONFIG_DEFAULT_FILE=mac_cross_cp0_config_defaults.mk CONFIG_TOOLCHAIN_PATH=/opt/homebrew/bin \
    CONFIG_GCC_DUMPMACHINE=aarch64-linux-gnu scons -j8
```

AppStore links `-l:libcurl.so.4`, which Apple's linker does not understand, so
run its simulator through linux-sim (below).

## CMake projects

```bash
# CardputerZero-Emulator: the launcher inside a picture of the device
cd projects/CardputerZero-Emulator
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build -j8
cd build && ./cardputer-zero-emu                      # or: ./cardputer-zero-emu apps/libUserDemo.dylib
# Your own apps in it: ./cardputer-zero-emu --fb -- <app>, or scripts/emulator_install.py (emulator.md)

# Keyboard-Guide
cd projects/Keyboard-Guide/main_Keyboard-Guide
./bootstrap.sh
cmake -S . -B build/sdl -DKEYBOARD_GUIDE_USE_SDL=ON && cmake --build build/sdl -j8
./dist/M5CardputerZero-Keyboard-Guide
cmake -S . -B build/cp0 -DKEYBOARD_GUIDE_USE_SDL=OFF -DCMAKE_TOOLCHAIN_FILE=cmake/aarch64-linux-gnu.cmake
cmake --build build/cp0 -j8                            # device binary
git checkout -- src/assets/assets.h                    # the build regenerates this tracked file

# CameraApp desktop preview (camera is simulated)
cd projects/CameraApp/main_CameraApp
cmake --preset darwin-arm64 -DMINIAUDIO_INCLUDE_DIR=$PWD/../../../ext_components/Miniaudio/include \
      "-DCMAKE_CXX_FLAGS=-include $(brew --prefix)/include/fmt/format.h"   # newer fmt needs this
cmake --build --preset darwin-arm64-rel
./build/darwin-arm64/Release/camera_app
```

CameraApp's device build (`cmake --preset cp0-cross`) needs a sysroot with
libcamera **0.7.2** headers; the published SDK sysroots ship 0.7.0, so it fails
until a newer sysroot is published (build it in CameraApp's own CI instead).

## Linux-only projects and test suites: linux-sim

`scripts/linux-sim/linux-sim.sh` builds and runs projects inside a Debian
container (Docker, OrbStack, ...) using its own copy of the repository, so your
host `build/` and `dist/` folders are not touched:

```bash
scripts/linux-sim/linux-sim.sh run LaunchWizard          # then: open vnc://localhost:5900  (password: cardputer)
scripts/linux-sim/linux-sim.sh shot ZClaw zclaw.png      # headless screenshot
scripts/linux-sim/linux-sim.sh test applaunch            # also: cp0_lvgl | zclaw | launchwizard
scripts/linux-sim/linux-sim.sh shell                     # anything else
```

The VNC view is exactly the 320x170 screen and forwards your keyboard.

## Test suites

| Suite | Command | Where |
| --- | --- | --- |
| APPLaunch (C++ + Python contracts) | `sh projects/APPLaunch/tests/run_tests.sh` | Linux (linux-sim on macOS) |
| cp0_lvgl | `sh ext_components/cp0_lvgl/tests/run_tests.sh` | macOS or Linux |
| ZClaw | `sh projects/ZClaw/tests/run_tests.sh` | Linux, as a non-root user; two tests need network/filesystem conditions |
| LaunchWizard | `cmake --preset dev && cmake --build --preset dev && ctest --preset dev` | Linux |

## Known issues

- **ZClaw on macOS**: the app runs and renders frames correctly, but the macOS
  window stays black (not yet understood; Linux is fine). Use
  `linux-sim.sh run ZClaw`.
- **CameraApp device build**: blocked on the libcamera version in the sysroot (above).
- **AppStore native macOS build**: needs an upstream change from `-l:libcurl.so.4` to `-lcurl` on macOS.
