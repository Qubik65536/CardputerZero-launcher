/*
 * SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
 *
 * SPDX-License-Identifier: MIT
 */

#include "hal_lvgl_bsp.h"
#include "lvgl/lvgl.h"
#include "sdl_lvgl.h"
#include "../cp0_display_screenshot_contract.hpp"


#include "lvgl/src/drivers/sdl/lv_sdl_mouse.h"
#include "lvgl/src/drivers/sdl/lv_sdl_private.h"
#include "lvgl/src/drivers/sdl/lv_sdl_window.h"

#include "input_keys.h"
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *getenv_default(const char *name, const char *dflt)
{
    const char *value = getenv(name);
    return (value && value[0] != '\0') ? value : dflt;
}

static atomic_int s_quit_requested = 0;

int cp0_sdl_quit_requested(void)
{
    return atomic_load(&s_quit_requested);
}

/* Runs on whichever thread queues the event (SDL's signal handler included), so it
 * only records the request. Returning 0 drops the event before LVGL's SDL driver
 * sees it: its SDL_QUIT path calls lv_deinit() and exit() mid-timer, which runs
 * static destructors while pages, threads and LVGL objects are still alive. */
static int quit_event_filter(void *userdata, SDL_Event *event)
{
    (void)userdata;
    if (event->type == SDL_QUIT ||
        (event->type == SDL_WINDOWEVENT && event->window.event == SDL_WINDOWEVENT_CLOSE)) {
        atomic_store(&s_quit_requested, 1);
        return 0;
    }
    return 1;
}

void init_sdl_disp(void)
{
    static pthread_mutex_t init_mutex = PTHREAD_MUTEX_INITIALIZER;
    pthread_mutex_lock(&init_mutex);
    if (lv_display_get_default() != NULL) {
        pthread_mutex_unlock(&init_mutex);
        return;
    }

    int width = cp0_display_dimension_or_default(getenv("LV_SDL_VIDEO_WIDTH"), 320);
    int height = cp0_display_dimension_or_default(getenv("LV_SDL_VIDEO_HEIGHT"), 170);
    lv_display_t *disp = lv_sdl_window_create(width, height);
    if (disp == NULL) {
        fprintf(stderr, "cp0_lvgl: failed to create SDL display\n");
        pthread_mutex_unlock(&init_mutex);
        return;
    }

    lv_sdl_window_set_title(disp, getenv_default("LV_SDL_WINDOW_TITLE", "M5CardputerZero"));
    SDL_SetEventFilter(quit_event_filter, NULL);
    pthread_mutex_unlock(&init_mutex);
}

void init_freambuffer_disp(void)
{
    init_sdl_disp();
}
