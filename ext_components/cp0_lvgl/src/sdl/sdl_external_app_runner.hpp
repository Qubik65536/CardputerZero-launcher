/*
 * SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
 *
 * SPDX-License-Identifier: MIT
 */

#pragma once

namespace sdl_external_app_runner {

int run(const char *command);

} // namespace sdl_external_app_runner

/*
 * Host hooks for run(). cp0_lvgl provides weak no-op defaults; a host that owns
 * the screen (the CardputerZero emulator) overrides them to show the external
 * app inside its own window, the way the device hands its framebuffer over:
 *
 *   env()        extra "NAME=value" entries for the app's environment, NULL-
 *                terminated (e.g. the fbsim CARDPUTER_FB / CARDPUTER_INPUT
 *                contract), or NULL for none. Called before fork().
 *   begin(pid)   the app started as process group `pid`.
 *   tick()       called repeatedly on the calling (LVGL) thread while the app
 *                runs; pump events and draw here. Returns the milliseconds to
 *                sleep before the next call.
 *   end()        the app's process group is gone.
 */
extern "C" {
const char *const *cp0_sdl_external_app_env(void);
void cp0_sdl_external_app_begin(int pid);
int cp0_sdl_external_app_tick(void);
void cp0_sdl_external_app_end(void);
}
