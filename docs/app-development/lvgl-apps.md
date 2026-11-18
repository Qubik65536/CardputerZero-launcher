<!-- SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
     SPDX-License-Identifier: MIT -->
# LVGL apps in Rust, Zig and OCaml

Each language has two templates. The `*-fb` ones draw pixels into the
framebuffer themselves; the `*-lvgl` ones (`rust-lvgl`, `zig-lvgl`,
`ocaml-lvgl`) build their screens from [LVGL](https://docs.lvgl.io/9.5/)
widgets, like the launcher and the [C++ template](cpp-lvgl.md). Both kinds
are the same app (home screen, Colors, Motion, REPL, Widgets), so you can
compare them side by side.

## Framebuffer or LVGL?

| | Framebuffer (`*-fb`) | LVGL (`*-lvgl`) |
| --- | --- | --- |
| **Idea** | You own every pixel: fill rectangles, draw text, `present()` | You create objects (labels, buttons, sliders, lists) and LVGL draws them |
| **Text, fonts** | One built-in 8x16 bitmap font | Many sizes, proportional fonts, TrueType via FreeType |
| **Forms, lists, scrolling** | Write them yourself (see the hand-drawn Widgets demo) | Ready-made: text areas, buttons, sliders, spinboxes, dropdowns, switches, checkboxes, lists, tabs, charts, ...; focus groups, scrolling and editing included (see the LVGL Widgets demo) |
| **Layout** | Coordinates you compute | Alignment, flex and grid layouts, styles |
| **Looks like the launcher** | Only if you copy the look | The standard top bar (title, clock, Wi-Fi, battery) is built in |
| **Animation, games** | Natural: redraw every frame | Possible (timers, animations, `lv_canvas` for pixels), but widgets are not a game engine |
| **Dependencies** | None: two Linux files | The LVGL runtime (built once with one command) |
| **Device build** | Trivial (Zig: no toolchain at all) | Needs the device sysroot and, for Rust, the aarch64 cross gcc |
| **Calling it** | Plain functions of the language | Foreign calls into C, through a bindings file you can extend |

Pick **framebuffer** for games, visualizations and anything where you want to
understand every step. Pick **LVGL** for apps with text input, menus, settings
and forms, or apps that should feel like the built-in ones: the widgets do the
hard work (focus, editing, scrolling, styling).

## How it fits together

```
your app (Rust / Zig / OCaml)
   │  calls C functions declared in src/lvgl.rs | src/lvgl.zig | src/lvgl_stubs.c + lvgl.ml
   ▼
cp0_app.h  ── cp0_app_run(title, setup, on_key, user_data), cp0_app_quit(), ...
   │          (ext_components/cp0_lvgl/include/cp0_app.h)
   ▼
cp0_lvgl + LVGL 9.5   ── display (SDL window / fbsim / device panel), keyboard,
                         top bar, platform services
```

`cp0_app_run` starts everything and shows a standard page: the 20 px top bar
and a 320x150 content area. It calls your `setup` function with that content
area, where you create widgets with ordinary LVGL calls (`lv_label_create`,
`lv_obj_align`, ...). Every key press reaches your `on_key` function with the
Linux key code and the text it types. `cp0_app_quit()` ends the app.

The C code is built once into the **LVGL runtime**:

```bash
source ~/cardputer-venv/bin/activate             # the Python environment from setup.md
scripts/lvgl-runtime/build.sh desktop            # once per machine (and after pulling LVGL/cp0_lvgl changes)
scripts/lvgl-runtime/build.sh device             # once, before the first device build
```

It writes the libraries and the exact link flags to
`scripts/lvgl-runtime/out/<desktop|device>/`, and each template's build
(`build.rs`, `build.zig`, dune) reads them. See
[scripts/lvgl-runtime](../../scripts/lvgl-runtime/README.md).

## Create, run, ship

```bash
python3 scripts/new_app.py rust-lvgl "Pixel Pet"   # or zig-lvgl, ocaml-lvgl
cd projects/PixelPet
```

| | Rust | Zig | OCaml |
| --- | --- | --- | --- |
| Run on your computer | `cargo run` | `zig build run` | `dune build && ./_build/default/src/main.exe` |
| Tests | `cargo test` | `zig build test` | `dune test` |
| Device binary | `cargo build --release --target aarch64-unknown-linux-gnu` | `zig build device` | `./device/build-device.sh` (Docker) |
| Package | `python3 ../../scripts/package_app.py .` | same | same |

Run from the app's directory: on your computer, images are found under
`./APPLaunch/share/images/`. The desktop build opens an SDL window; started by
`fbsim`, `headless.py` or the [emulator](emulator.md) it draws into their
screen instead, so screenshots and scripted tests work as for the other
templates:

```bash
python3 ../../scripts/fbsim/headless.py --settle 2.5 --keys "4 shift+a d a enter enter" \
    --png form.png -- ./target/debug/pixel-pet
```

On the device the app links against libraries every CardputerZero has
(libinput, xkbcommon, FreeType, libstdc++, ...), so the package contains only
your binary and resources.

## Calling more of LVGL

The templates declare only the LVGL functions the demo uses, in one file:
`src/lvgl.rs` (Rust), `src/lvgl.zig` (Zig), `src/lvgl_stubs.c` + `src/lvgl.ml`
(OCaml, which calls C through small stub functions). To use another widget or
function:

1. Look it up in the [LVGL 9.5 docs](https://docs.lvgl.io/9.5/) and find its C
   declaration under `SDK/github_source/lvgl/lvgl_9_5/lvgl/src/` (for example
   `widgets/chart/lv_chart.h`).
2. Copy the signature into the bindings file, following the ones already
   there. Pointers to LVGL objects are opaque; `lv_color_t` is a 3-byte struct
   (`blue, green, red`) passed by value; `int32_t` coordinates; enums are
   C `int`s; style selectors and states are `uint32_t`.
3. Constants (`LV_ALIGN_CENTER`, `LV_EVENT_CLICKED`, `LV_PART_INDICATOR`, ...)
   are C enums or macros: copy their values from the same headers.
   Function-like macros and `static inline` functions (such as `LV_PCT`) have no
   symbol to call; write them in your language.
4. In OCaml, also add a stub to `lvgl_stubs.c` that converts the arguments.

Everything LVGL provides is compiled into the runtime, so no rebuild of the
runtime is needed for new widgets. Keep LVGL calls on the LVGL thread: in
`setup`, `on_key`, event callbacks and `lv_timer` callbacks.

## Looks: the theme

The templates start LVGL's default theme in dark mode with the language's
color as its primary color (`lv_theme_default_init`, before any widget exists).
Widgets created afterwards take their look from it: rounded buttons, focus
outlines, slider and switch colors, dropdown lists. Calling it again with
another color restyles every themed widget at once, which is what the Widgets
demo's Color dropdown does. Set individual styles (`lv_obj_set_style_*`) only
where you want to differ from the theme.

## Keys and focus

Keys reach your app twice, and you can use either path:

- **Your `on_key` callback** gets every key, presses and releases (`state`),
  with `code` (the Linux key code) and `text` (what it types, with Shift and
  the symbol layer applied). Use it for app-wide keys (the demos: ESC goes
  home, TAB to the next demo) and screens that are not made of widgets.
- **LVGL's keypad input** delivers the same keys to the focused widget of the
  active `lv_group`, the standard LVGL way: ENTER clicks a button, toggles a
  switch or opens a dropdown; LEFT/RIGHT move a slider; typed characters go
  into a focused `lv_textarea`, which also handles BACKSPACE and cursor keys
  itself; ESC closes a dropdown list.

The Widgets demo is built this way: an `lv_group` holds the form's widgets,
and everything is stock LVGL (default theme, flex layout, widget events)
except two small things the CardputerZero keyboard needs:

- **Moving the focus.** LVGL moves focus on its NEXT/PREV keys, which the
  device keyboard doesn't have. The device has no arrow keys either: F/X/Z/C
  act as up/down/left/right, as in the launcher (real arrows work on your
  computer). So each widget gets a preprocess `LV_EVENT_KEY` handler that turns
  up/down into `lv_group_focus_prev/next` (except in an open dropdown list,
  where up/down choose an option).
- **Text mode.** While a text area has focus, `cp0_app_set_text_input(1)` makes
  F/X/Z/C type letters instead of navigating; set it back to 0 when it loses
  focus (the text area's `LV_EVENT_FOCUSED`/`DEFOCUSED` events).

`cp0_app_set_keypad_intercept(1)` (in `cp0_app.h`; add it to your bindings if
your template doesn't declare it) turns the second path off, for screens that
want to handle every key in `on_key` themselves. See the comments at the top of
each template's widgets source, and the C++ guide's
[keyboard section](cpp-lvgl.md#keyboard).

## Troubleshooting

| Problem | Fix |
| --- | --- |
| "LVGL runtime not built" | Run `scripts/lvgl-runtime/build.sh desktop` (or `device`) |
| Undefined `lv_*` / `cp0_*` symbols after pulling | Rebuild the runtime: LVGL or cp0_lvgl changed |
| Crash or garbage after adding a binding | Compare the declaration with the C header: argument types, `lv_color_t` by value, enum values |
| The wallpaper is missing | Run from the app's directory, so `./APPLaunch/share/images` exists |
| Device link errors about the sysroot | Run `scripts/lvgl-runtime/build.sh device` once (it downloads the sysroot) |
