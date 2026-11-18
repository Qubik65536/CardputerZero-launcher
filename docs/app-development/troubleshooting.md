<!-- SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
     SPDX-License-Identifier: MIT -->
# Troubleshooting

First stop for anything on the device: the launcher's log, which also contains
your app's output.

```bash
ssh pi@<device-ip> journalctl --user -u APPLaunch.service -f
```

## The app does not appear on the home screen

The launcher logs why it skipped a `.desktop` file. Common causes:

| Cause | Fix |
| --- | --- |
| File not in `/usr/share/APPLaunch/applications/` or not ending in `.desktop` | That is the only directory scanned |
| `Exec` is not an absolute path to an executable file | `ls -l` it on the device; `chmod +x`; make sure it is the aarch64 build |
| `Exec` contains `\| & ; < > \` $ \\` | Use a wrapper script without those characters, or pass plain arguments |
| `Exec` is the same as another entry or a built-in app (e.g. `python3`) | Give your app its own executable |
| `Icon` cannot be resolved | Use `share/images/<file>.png` and install the file there; no `..`, no paths outside `/usr/share/APPLaunch` |
| `Type=` is something other than `Application` | Remove it or set `Application` |
| `Hidden=true` / `NoDisplay=true` | Remove them |

`scripts/package_app.py` checks most of these before building the package.

## The app starts, then immediately returns to the home screen

The process exited. Look in the journal for its error message. Typical ones:

- `cannot execute binary file` / `Exec format error`: you installed the desktop build. Build for aarch64.
- `GLIBC_2.xx not found`: built against a newer glibc than the device's 2.41. Use the cross toolchains or a Debian trixie container (Zig device builds are static and avoid this).
- `error while loading shared libraries: libfoo.so`: the library is not on the device. Install it (and add it to `depends` in `cardputer-app.json`), link it statically, or avoid it.
- `No such file or directory` for an asset: the app runs in `/usr/share/APPLaunch`; use absolute paths.
- `Permission denied` on `/dev/fb*` or `/dev/input/*`: only when started outside the launcher; see [framebuffer apps](framebuffer-apps.md#running-on-the-device).

## The screen shows "Loading..." or garbage while my app runs

The launcher hands over the screen without clearing it. Draw a complete frame
as soon as your app starts and after any change.

## Keys do nothing / arrows don't work

- The device has no arrow keys: handle F/X/Z/C (up/down/left/right), as the templates' `direction()` does.
- Symbols arrive with special key codes; see [device reference](device-reference.md#key-codes).
- Don't grab the keyboard (`EVIOCGRAB`).
- LVGL apps: key events go to the active screen; attach your handler to `root_screen_` (`LV_EVENT_KEY` or `LV_EVENT_KEYBOARD`).

## ESC doesn't quit / the app has to be force-closed

Handle a short ESC press and exit (return from `main`). Holding ESC for 3 s
makes the launcher send SIGTERM and then SIGKILL to the app's whole process
group, which also takes background children with it.

## Building

| Symptom | Fix |
| --- | --- |
| SCons from the repo root fails | Run `scons` inside the project directory |
| Device build produces a macOS/x86 binary, or config looks stale | `scons distclean`, then build with the right `CONFIG_DEFAULT_FILE` |
| `aarch64-linux-gnu-g++: command not found` (macOS) | `brew tap messense/macos-cross-toolchains && brew install aarch64-unknown-linux-gnu`; the projects find it on your `PATH` |
| Build hangs at a prompt about missing sources | `export CONFIG_REPO_AUTOMATION=y` |
| `SDL2/SDL.h` not found | Install SDL2 (`brew install sdl2` / `apt install libsdl2-dev`) and `pkg-config` |
| Rust: `linker aarch64-linux-gnu-gcc not found` | Install the cross gcc ([setup](setup.md)) |
| Zig: errors in `std.Io` / `std.posix` | Use Zig 0.17.x; other versions have different standard library APIs |
| OCaml: device build fails with `exec format error` in Docker | Your Docker cannot run arm64 containers: enable QEMU emulation, or build on the device |
| fbsim: window stays black | The app has not written a frame yet, or it is not using `CARDPUTER_FB`. Check its stderr in the terminal |
| Emulator: app missing from the home screen | Run `scripts/emulator_install.py` after building the desktop version; the launcher's stderr says why it skipped an entry (`applications_load: skip ...`) |
| Emulator: `emulator_install.py` says "Linux build for another CPU" | That is the device build; build for your computer and set `desktop_binary` |
| Emulator: the app opens its own window | It ignores `CARDPUTER_FB`. LVGL apps need a cp0_lvgl from this repository (rebuild after updating) |

## Simulator vs. device differences

- Simulator windows are 320x170 like the device, but your monitor makes text look bigger: check readability on the real screen.
- Desktop keyboards have arrow keys and the device doesn't; test with F/X/Z/C.
- Network, Wi-Fi, battery and audio services are simulated or absent on the desktop.
- Performance: the device CPU is far slower than your computer. Redraw only when needed.
