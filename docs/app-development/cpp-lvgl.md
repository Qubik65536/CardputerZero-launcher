<!-- SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
     SPDX-License-Identifier: MIT -->
# C++ / LVGL apps

The `cpp-lvgl` template builds apps the way the launcher's own apps are built:
[LVGL 9.5](https://docs.lvgl.io/9.5/) widgets on top of **cp0_lvgl**, the
CardputerZero platform layer (`ext_components/cp0_lvgl/`). cp0_lvgl provides
the display (an SDL window on your computer, the framebuffer on the device),
the keyboard with device-accurate key codes, the standard top bar, and
optional services (audio, Wi-Fi, battery, config storage, ...).

## Create, run, ship

```bash
source ~/cardputer-venv/bin/activate && export CONFIG_REPO_AUTOMATION=y
python3 scripts/new_app.py cpp-lvgl "Weather Station"    # -> projects/WeatherStation/ (must stay there)
cd projects/WeatherStation

scons -j8 && (cd dist && ./weather-station)               # simulator window
CONFIG_DEFAULT_FILE=linux_x86_cross_cp0_config_defaults.mk scons -j8   # device binary in dist/
python3 ../../scripts/package_app.py .                    # packages/weather-station_0.1.0_arm64.deb
```

The first device build downloads the device sysroot (~440 MB). Profiles:

| Profile | Builds | Default when |
| --- | --- | --- |
| `darwin_config_defaults.mk` | macOS simulator (Apple clang + Homebrew SDL2) | on macOS |
| `linux_x86_sdl2_config_defaults.mk` | Linux simulator (any CPU) | on Linux x86_64 |
| `linux_x86_cross_cp0_config_defaults.mk` | Device binary, from macOS or Linux | `CardputerZero=y` |
| `config_defaults.mk` | Device binary, built on the device | on aarch64 Linux |

Profiles are Kconfig fragments. `CONFIG_V9_5_LV_*` options configure LVGL and
`CONFIG_CP0_LVGL_INIT_*` options turn on platform services. Keep the profiles
you use in sync when you add options.

## Project tour

| File | Contents |
| --- | --- |
| `main/src/main.cpp` | `cp0_lvgl_run_app<WeatherStationPage>(hooks)`: sets up everything, shows the page, runs the event loop until `hooks.should_quit` returns true |
| `main/ui/weather_station_page.{hpp,cpp}` | The page: widgets in `create_ui()`, keys in `handle_key()` |
| `main/SConstruct` | Sources (everything under `main/src` and `main/ui`), libraries, executable name |
| `APPLaunch/` | Resources copied to `dist/APPLaunch/` (simulator) and installed to `/usr/share/APPLaunch/` (device): `.desktop`, icons in `share/images/`, fonts in `share/font/` |

## Pages

All page classes come from `ext_components/cp0_lvgl/include/ui_app_page.hpp`:

| Base class | You get |
| --- | --- |
| `AppPage` | 20 px top bar (title, clock, Wi-Fi, battery) + `ui_APP_Container` (320 x 150) for your widgets. `set_page_title("...")` |
| `AppPage` + `AppPageWithBottomBarLayout` | Also `ui_BOTTOM_Container` (320 x 20 at the bottom); the content area shrinks to 130 px |
| `AppPageRoot` | A blank black 320 x 170 screen (`root_screen_`), for full-screen apps and games |

Build the UI with ordinary LVGL calls on `ui_APP_Container`: labels, buttons,
lists, bars, images, flex/grid layouts. The LVGL documentation applies as-is.
Several screens: create one page object per screen and call
`cp0_lvgl_start_app_page(*page)` to show it (see `cp0_lvgl_app_runner.hpp`).

**Quitting.** A standalone app quits when `should_quit` returns true; the
template sets a flag on ESC. (`navigate_home` is only wired up for pages built
into the launcher.) If you never quit, holding ESC for 3 s makes the launcher
kill the app.

## Keyboard

The template uses LVGL's key event:

```cpp
lv_obj_add_event_cb(root_screen_, key_event_cb, LV_EVENT_KEY, this);
// in the callback:
uint32_t key = cp0_keyboard_navigation_alias(lv_event_get_key(event));  // F/X/Z/C -> arrows
if (key == LV_KEY_UP) ...  else if (key == LV_KEY_ENTER) ...  else if (key == LV_KEY_ESC) ...
```

For text input and full detail, listen for `LV_EVENT_KEYBOARD` (from
`keyboard_input.h`; it is a variable, so cast it), whose parameter is a
`const key_item *`: `key_code` (Linux code), `utf8` (the produced text,
symbols already translated), `mods` (`KBD_MOD_SHIFT`, `KBD_MOD_CTRL`,
`KBD_MOD_FN`, ...), `key_state` (0 released, 1 pressed, 2 repeat):

```cpp
lv_obj_add_event_cb(root_screen_, [](lv_event_t *e) {
    if (lv_event_get_code(e) != static_cast<lv_event_code_t>(LV_EVENT_KEYBOARD)) return;
    auto *item = static_cast<const key_item *>(lv_event_get_param(e));
    if (item->key_state != 0 && item->utf8[0]) { /* append item->utf8 to your text */ }
}, LV_EVENT_ALL, this);
```

While a text field is focused, call
`cp0_keyboard_set_input_context(KBD_INPUT_CONTEXT_TEXT)` so F/X/Z/C type
letters instead of moving. Switch back to `KBD_INPUT_CONTEXT_NAVIGATION`
afterwards.

## Fonts

- **Built-in:** `&lv_font_montserrat_8` through `_48` (even sizes) are compiled in by the profiles. Use 12 px or larger for UI text.
- **TrueType:** add `CONFIG_V9_5_LV_USE_FREETYPE=y` and
  `CONFIG_CP0_LVGL_INIT_FILESYSTEM=y` to your profiles (the device profile
  already has FreeType). Then use
  `cp0_fonts().get("DejaVuSans.ttf", 16)` (`#include "cp0_font_service.hpp"`).
  The device ships DejaVuSans, DejaVuSansMono, DejaVuSerif, JetBrainsMono,
  LiberationMono, Montserrat-Bold, AlibabaPuHuiTi and Noto Sans/Serif CJK in
  `/usr/share/APPLaunch/share/font/`. For the simulator, copy the fonts you use
  into your `APPLaunch/share/font/` (from `projects/APPLaunch/APPLaunch/share/font/`).

## Images

Put PNGs in `APPLaunch/share/images/` and load them by name:

```cpp
lv_obj_t *icon = lv_image_create(ui_APP_Container);
lv_image_set_src(icon, cp0_file_path("weather-station_100.png").c_str());  // #include "cp0_lvgl_filesystem.hpp"
```

`cp0_file_path` returns the right path for the simulator and for the device
(where LVGL's `A:` drive is `/usr/share/APPLaunch/`).

## Platform services

cp0_lvgl exposes the hardware and the system through `cp0_signal_*` functions:
audio playback, Wi-Fi/network status, battery, settings storage
(`cp0_signal_config_api`), running processes, PTYs, screenshots, and more.
Enable a service with its `CONFIG_CP0_LVGL_INIT_<NAME>=y` profile option, then
call it as described in [docs/cp0_lvgl.en.md](../cp0_lvgl.en.md). Callbacks can
run on worker threads: hand results back to the LVGL thread (and call
`cp0_lvgl_wake()`) before touching widgets. The launcher (`projects/APPLaunch`)
and ZClaw are large examples of every service.

## Tips

- Don't run your own render loop or threads that touch LVGL; use `lv_timer_create` for periodic work.
- Logging: `printf`/`std::cerr`, or `SLOGI`/`SLOGE` from `sample_log.h` (add `utilities` to `REQUIREMENTS`). On the device, output goes to `journalctl --user -u APPLaunch.service`.
- Add sources anywhere under `main/src` or `main/ui`; SCons picks them up.
- Another library: add it to `REQUIREMENTS` in `main/SConstruct` (and to `LDFLAGS`/`INCLUDE` as needed). For the device it must exist in the sysroot (`SDK/github_source/static_lib_v0.0.7/usr/lib/aarch64-linux-gnu`) and on the device.
- If a build looks stale after editing profiles: `scons distclean`.
