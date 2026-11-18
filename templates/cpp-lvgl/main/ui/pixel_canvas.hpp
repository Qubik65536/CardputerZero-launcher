/*
 * SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
 *
 * SPDX-License-Identifier: MIT
 */

#pragma once

// Software rendering into an LVGL canvas: an RGB565 pixel buffer you draw into
// pixel by pixel, then present() so LVGL redraws it.

#include "lvgl/lvgl.h"

#include <cstdint>
#include <vector>

namespace app {

// Pack 0xRRGGBB into the RGB565 format of the canvas (and the panel).
constexpr uint16_t rgb565(uint32_t hex)
{
    return static_cast<uint16_t>(((hex >> 8) & 0xF800) | ((hex >> 5) & 0x07E0) | ((hex >> 3) & 0x001F));
}

// Mix two RGB565 colors: `alpha` 0 = all `under`, 255 = all `over`.
uint16_t blend565(uint16_t under, uint16_t over, uint8_t alpha);

class PixelCanvas
{
public:
    PixelCanvas(lv_obj_t *parent, int width, int height);

    PixelCanvas(const PixelCanvas &) = delete;
    PixelCanvas &operator=(const PixelCanvas &) = delete;

    int width() const { return width_; }
    int height() const { return height_; }
    lv_obj_t *obj() const { return canvas_; }

    void clear(uint16_t color);
    // Fill a rectangle; parts outside the canvas are clipped.
    void fill_rect(int x, int y, int width, int height, uint16_t color);
    // Set one pixel; coordinates outside the canvas are ignored.
    void set_pixel(int x, int y, uint16_t color);
    // Mix `color` over the pixel at (x, y); `alpha` 0 = invisible, 255 = opaque.
    void blend_pixel(int x, int y, uint16_t color, uint8_t alpha);
    // Darken a rectangle, e.g. behind text drawn over the picture. `alpha` 255 = black.
    void shade_rect(int x, int y, int width, int height, uint8_t alpha);
    // Fill a circle centered on (cx, cy), mixed in with `alpha`.
    void fill_circle(int cx, int cy, int radius, uint16_t color, uint8_t alpha);
    // Draw a 1-pixel line from (x0, y0) to (x1, y1) (Bresenham's algorithm).
    void draw_line(int x0, int y0, int x1, int y1, uint16_t color);
    // Show what was drawn since the last call.
    void present();

private:
    int width_;
    int height_;
    std::vector<uint16_t> pixels_;
    lv_obj_t *canvas_ = nullptr;
};

} // namespace app
