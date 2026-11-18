/*
 * SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
 *
 * SPDX-License-Identifier: MIT
 */

#include "sdl_fbsim.h"

#include "sdl_fbsim_keymap.h"
#include "../cp0_keyboard_queue.h"

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

enum {
    FBSIM_DEFAULT_WIDTH = 320,
    FBSIM_DEFAULT_HEIGHT = 170,
    FBSIM_EV_KEY = 0x01,
    FBSIM_INPUT_EVENT_SIZE = 24, /* struct input_event on 64-bit Linux */
};

static struct {
    uint16_t *pixels; /* mmap of CARDPUTER_FB */
    int width;
    int height;
    int input_fd;
    unsigned char partial[FBSIM_INPUT_EVENT_SIZE];
    size_t partial_len;
    uint32_t mods;
} s_fbsim = {NULL, 0, 0, -1, {0}, 0, 0};

static const char *nonempty_env(const char *name)
{
    const char *value = getenv(name);
    return (value && value[0] != '\0') ? value : NULL;
}

int cp0_fbsim_active(void)
{
    return nonempty_env("CARDPUTER_FB") != NULL;
}

static uint32_t fbsim_tick_ms(void)
{
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (uint32_t)((uint64_t)now.tv_sec * 1000u + (uint64_t)now.tv_nsec / 1000000u);
}

static void fbsim_parse_size(int *width, int *height)
{
    *width = FBSIM_DEFAULT_WIDTH;
    *height = FBSIM_DEFAULT_HEIGHT;
    const char *size = nonempty_env("CARDPUTER_FB_SIZE");
    int w = 0, h = 0;
    if (size && sscanf(size, "%dx%d", &w, &h) == 2 && w > 0 && h > 0 && w <= 4096 && h <= 4096) {
        *width = w;
        *height = h;
    }
}

static void fbsim_flush(lv_display_t *disp, const lv_area_t *area, uint8_t *px_map)
{
    const int32_t w = lv_area_get_width(area);
    const uint32_t stride = lv_draw_buf_width_to_stride((uint32_t)w, LV_COLOR_FORMAT_RGB565);
    for (int32_t y = area->y1; y <= area->y2; ++y) {
        if (y < 0 || y >= s_fbsim.height) continue;
        int32_t x1 = area->x1 < 0 ? 0 : area->x1;
        int32_t x2 = area->x2 >= s_fbsim.width ? s_fbsim.width - 1 : area->x2;
        if (x2 < x1) continue;
        const uint8_t *row = px_map + (size_t)(y - area->y1) * stride + (size_t)(x1 - area->x1) * 2;
        memcpy(&s_fbsim.pixels[(size_t)y * (size_t)s_fbsim.width + (size_t)x1], row,
               (size_t)(x2 - x1 + 1) * 2);
    }
    lv_display_flush_ready(disp);
}

static void *fbsim_map_framebuffer(const char *path, size_t size)
{
    int fd = open(path, O_RDWR);
    if (fd < 0) {
        fprintf(stderr, "cp0_lvgl: fbsim: cannot open %s: %s\n", path, strerror(errno));
        return NULL;
    }
    void *pixels = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    close(fd);
    if (pixels == MAP_FAILED) {
        fprintf(stderr, "cp0_lvgl: fbsim: cannot map %s: %s\n", path, strerror(errno));
        return NULL;
    }
    return pixels;
}

lv_display_t *cp0_fbsim_display_create(void)
{
    const char *path = nonempty_env("CARDPUTER_FB");
    if (!path) return NULL;
    fbsim_parse_size(&s_fbsim.width, &s_fbsim.height);
    const size_t size = (size_t)s_fbsim.width * (size_t)s_fbsim.height * 2;
    s_fbsim.pixels = fbsim_map_framebuffer(path, size);
    if (!s_fbsim.pixels) return NULL;

    /* LVGL's SDL window driver normally provides the tick; there is no window here. */
    lv_tick_set_cb(fbsim_tick_ms);

    lv_display_t *disp = lv_display_create(s_fbsim.width, s_fbsim.height);
    if (!disp) return NULL;
    lv_display_set_color_format(disp, LV_COLOR_FORMAT_RGB565);
    const uint32_t stride =
        lv_draw_buf_width_to_stride((uint32_t)s_fbsim.width, LV_COLOR_FORMAT_RGB565);
    const uint32_t buf_size = stride * (uint32_t)s_fbsim.height;
    void *buf = lv_malloc(buf_size);
    if (!buf) {
        lv_display_delete(disp);
        return NULL;
    }
    lv_display_set_buffers(disp, buf, NULL, buf_size, LV_DISPLAY_RENDER_MODE_PARTIAL);
    lv_display_set_flush_cb(disp, fbsim_flush);
    fprintf(stderr, "cp0_lvgl: fbsim display %dx%d on %s\n", s_fbsim.width, s_fbsim.height, path);
    return disp;
}

static int fbsim_open_input(void)
{
    if (s_fbsim.input_fd >= 0) return s_fbsim.input_fd;
    const char *path = nonempty_env("CARDPUTER_INPUT");
    if (!path) return -1;
    s_fbsim.input_fd = open(path, O_RDONLY | O_NONBLOCK);
    if (s_fbsim.input_fd < 0)
        fprintf(stderr, "cp0_lvgl: fbsim: cannot open %s: %s\n", path, strerror(errno));
    return s_fbsim.input_fd;
}

static uint16_t fbsim_get_u16(const unsigned char *in)
{
    return (uint16_t)(in[0] | (in[1] << 8));
}

static int fbsim_handle_record(const unsigned char *record)
{
    if (fbsim_get_u16(record + 16) != FBSIM_EV_KEY) return 0;
    const uint16_t code = fbsim_get_u16(record + 18);
    const int32_t value =
        (int32_t)((uint32_t)fbsim_get_u16(record + 20) | ((uint32_t)fbsim_get_u16(record + 22) << 16));
    struct key_item item;
    if (!cp0_fbsim_translate_key(code, value, &s_fbsim.mods, cp0_keyboard_get_input_context(),
                                 &item))
        return 0;
    return cp0_keyboard_queue_push(&item) == 0 ? 1 : 0;
}

int cp0_fbsim_input_poll(void)
{
    const int fd = fbsim_open_input();
    if (fd < 0) return 0;
    int queued = 0;
    unsigned char buf[FBSIM_INPUT_EVENT_SIZE * 16];
    for (;;) {
        const ssize_t got = read(fd, buf, sizeof(buf));
        if (got <= 0) break;
        for (ssize_t i = 0; i < got; ++i) {
            s_fbsim.partial[s_fbsim.partial_len++] = buf[i];
            if (s_fbsim.partial_len == FBSIM_INPUT_EVENT_SIZE) {
                queued += fbsim_handle_record(s_fbsim.partial);
                s_fbsim.partial_len = 0;
            }
        }
    }
    return queued;
}
