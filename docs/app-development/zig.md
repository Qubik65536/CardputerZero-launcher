<!-- SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
     SPDX-License-Identifier: MIT -->
# Zig apps

The `zig-fb` template is a Zig **0.17** program that draws into the
framebuffer and reads the keyboard. Read [framebuffer apps](framebuffer-apps.md)
first for the shared model; this page covers the Zig specifics.

Want widgets (text fields, lists, sliders) instead of pixels? The `zig-lvgl` template is the
same app built with LVGL: see [LVGL apps in Rust, Zig and OCaml](lvgl-apps.md).

## Create, run, ship

```bash
python3 scripts/new_app.py zig-fb "Pixel Pet"        # -> projects/PixelPet/
cd projects/PixelPet

zig build sim                                        # desktop, in fbsim (build scripts/fbsim first)
#   or in the emulator: cardputer-zero-emu --fb -- zig-out/bin/pixel-pet   (see emulator.md)
zig build device                                     # zig-out/device/pixel-pet: static aarch64 binary
python3 ../../scripts/package_app.py .               # packages/pixel-pet_0.1.0_arm64.deb
```

`zig build device` needs no cross toolchain, sysroot or Docker. The binary
does not link libc (Zig's standard library talks to the Linux kernel
directly), so it is fully static and runs regardless of the device's glibc.
If the app is not inside the launcher repository, point `sim` at fbsim:
`zig build sim -Dfbsim=/path/to/launcher/scripts/fbsim/fbsim`.

**Zig version:** the template targets 0.17 (`build.zig.zon` →
`minimum_zig_version`). Zig's standard library changes between releases, I/O
especially; on a newer Zig, expect to adjust `display.zig` (`std.Io` file
calls) and `input.zig` (`std.posix`).

## Project tour

The app is described in [framebuffer apps](framebuffer-apps.md#the-template-app):
a home screen and four demos.

| File | Contents |
| --- | --- |
| `src/main.zig` | `App` (the current `Screen` and each screen's state), `handleKey`, `tick`, `draw`, and `main(init: std.process.Init)` with the loop |
| `src/ui.zig` | `language`, `language_color` and the palette; `drawHeader`, `drawHint`, `drawShadowedText`; `Action` |
| `src/home.zig` | The home screen: wallpaper (`@embedFile("wallpaper.rgb565")`), greeting, menu (`demos`) |
| `src/colors.zig` | RGB triangle (barycentric shading) and HSV wheel |
| `src/motion.zig` | The ball: momentum, bounces, trail, sparks; the physics readout and speed graph |
| `src/repl.zig` | The terminal-style screen: scrollback, input line, history, `help`/`vars`/`clear` |
| `src/widgets.zig` | The widget form: `Widget` rows, focus, `change` (Z/C) and `activate` (ENTER), one `draw*` function per widget |
| `src/calc.zig` | The calculator language (`Calculator.run(line)` returns `.ok` or `.err` text) and its `test` blocks |
| `src/display.zig` | `Display.open(io, env)`, `clear`, `fillRect`, `setPixel`, `blendPixel`, `shadeRect`, `strokeRect`, `drawLine`, `fillCircle`, `drawImage`, `drawText`, `Display.textWidth`, `present`, `close`; `rgb(r, g, b)`, `blend(under, over, alpha)`, `black`, `white`, `char_width`, `char_height` |
| `src/input.zig` | `Keyboard.open(env)`, `poll() !?KeyEvent`, `close(io)`; `KeyEvent{ code, state }`, `isDown()`; `keys.*`; `direction(code) ?Direction`; `Typist.init(env)`, `charFor(event) ?u8` |
| `src/font.zig` | The 8x16 glyph table |
| `src/wallpaper.rgb565` | The home screen's 320x170 picture |
| `build.zig` | `zig build`, `zig build sim`, `zig build device`, `zig build test` |

`Display` holds about 220 KB of buffers, so `main.zig` keeps it in a global
(`var screen: Display = undefined;`) rather than on the stack. `main` receives
`init.io` (the `std.Io` implementation), `init.environ_map` (environment
variables) and `init.gpa` (an allocator, used by the REPL for its history and
the calculator's variables), which the modules use.

## Common tasks

**Start from one demo.** Delete the screens you don't want: remove the
import, its field and `Screen` value in `main.zig`, its entry in
`demo_screens` and in `home.demos`. Or make one demo the whole app by starting
`App` on its screen.

**A new screen.** Copy the shape of `motion.zig`: a struct with
`handleKey(event) Action`, `draw(display)` and, if it animates, `tick()`.
Add a `Screen` value, the `switch` prongs in `main.zig`, and entries in
`home.demos` and `demo_screens`.

**Timed updates.** `App.tick` runs every frame; the demos advance by one frame
per tick. For speed that doesn't depend on the frame rate, read a clock
(`std.Io.Clock.awake.now(io)`) and pass the difference to your update.

**Text input.** Pass every event to `typist.charFor` (see `main`), then use the
character in the screen that wants text, as `Repl.handleKey` and the Widgets
text field do.

**Forms and widgets.** `widgets.zig` shows the pattern: a list of rows, one
focused index, and per-widget functions to change, activate and draw. Add a
row by adding a `Widget` value, its label in `rows`, and prongs in `change`,
`activate` and `draw`.

**Images.** Convert with `scripts/png_to_rgb565.py art/player.png src/player.rgb565 --alpha`
(keep the file under `src/` so `@embedFile` can reach it) and draw with
`screen.drawImage(10, 30, @embedFile("player.rgb565"))`. A new wallpaper:
`python3 ../../scripts/png_to_rgb565.py my-picture.png src/wallpaper.rgb565`
with a 320x170 PNG.

**Saving data.** `init.environ_map.get("HOME")` gives `/home/pi`; use
`std.Io.Dir` to create `~/.local/share/<app>/` and write files.

**C libraries.** Zig compiles and links C directly (`exe.root_module.addCSourceFile`,
`linkSystemLibrary`). Linking a device library (e.g. libpulse) means linking
glibc too: target `aarch64-linux-gnu.2.36` and provide the device sysroot (the
SCons projects download one to `SDK/github_source/static_lib_v0.0.7`).

## Testing

```bash
zig build test                                     # the `test` blocks (calc.zig and motion.zig have some)
zig build && python3 ../../scripts/fbsim/headless.py \
    --keys "3 6 shift+8 7 enter" --png /tmp/shot.png -- ./zig-out/bin/pixel-pet
```
