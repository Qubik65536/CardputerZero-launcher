/*
 * SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
 *
 * SPDX-License-Identifier: MIT
 */

#include "pixel_canvas.hpp"

#include <algorithm>
#include <cstdlib>

namespace app {

namespace {

uint16_t mix_channel(uint16_t under, uint16_t over, uint32_t alpha, int shift, uint32_t mask)
{
    const uint32_t below = (static_cast<uint32_t>(under) >> shift) & mask;
    const uint32_t above = (static_cast<uint32_t>(over) >> shift) & mask;
    return static_cast<uint16_t>(((below * (255 - alpha) + above * alpha + 127) / 255) << shift);
}

} // namespace

uint16_t blend565(uint16_t under, uint16_t over, uint8_t alpha)
{
    return mix_channel(under, over, alpha, 11, 0x1F) | mix_channel(under, over, alpha, 5, 0x3F) |
           mix_channel(under, over, alpha, 0, 0x1F);
}

PixelCanvas::PixelCanvas(lv_obj_t *parent, int width, int height)
    : width_(width), height_(height), pixels_(static_cast<size_t>(width) * height)
{
    canvas_ = lv_canvas_create(parent);
    lv_canvas_set_buffer(canvas_, pixels_.data(), width, height, LV_COLOR_FORMAT_RGB565);
    lv_obj_set_pos(canvas_, 0, 0);
}

void PixelCanvas::clear(uint16_t color)
{
    std::fill(pixels_.begin(), pixels_.end(), color);
}

void PixelCanvas::fill_rect(int x, int y, int width, int height, uint16_t color)
{
    const int left = std::clamp(x, 0, width_);
    const int right = std::clamp(x + width, 0, width_);
    const int top = std::clamp(y, 0, height_);
    const int bottom = std::clamp(y + height, 0, height_);
    for (int row = top; row < bottom; ++row) {
        uint16_t *line = &pixels_[static_cast<size_t>(row) * width_];
        std::fill(line + left, line + right, color);
    }
}

void PixelCanvas::set_pixel(int x, int y, uint16_t color)
{
    if (x >= 0 && y >= 0 && x < width_ && y < height_) pixels_[static_cast<size_t>(y) * width_ + x] = color;
}

void PixelCanvas::blend_pixel(int x, int y, uint16_t color, uint8_t alpha)
{
    if (x >= 0 && y >= 0 && x < width_ && y < height_) {
        uint16_t &pixel = pixels_[static_cast<size_t>(y) * width_ + x];
        pixel = blend565(pixel, color, alpha);
    }
}

void PixelCanvas::fill_circle(int cx, int cy, int radius, uint16_t color, uint8_t alpha)
{
    for (int dy = -radius; dy <= radius; ++dy) {
        for (int dx = -radius; dx <= radius; ++dx) {
            if (dx * dx + dy * dy <= radius * radius + radius) blend_pixel(cx + dx, cy + dy, color, alpha);
        }
    }
}

void PixelCanvas::shade_rect(int x, int y, int width, int height, uint8_t alpha)
{
    for (int row = y; row < y + height; ++row) {
        for (int column = x; column < x + width; ++column) blend_pixel(column, row, 0x0000, alpha);
    }
}

void PixelCanvas::draw_line(int x0, int y0, int x1, int y1, uint16_t color)
{
    const int dx = std::abs(x1 - x0);
    const int dy = -std::abs(y1 - y0);
    const int step_x = x0 < x1 ? 1 : -1;
    const int step_y = y0 < y1 ? 1 : -1;
    int x = x0;
    int y = y0;
    int error = dx + dy;
    for (;;) {
        set_pixel(x, y, color);
        if (x == x1 && y == y1) break;
        const int doubled = 2 * error;
        if (doubled >= dy) {
            error += dy;
            x += step_x;
        }
        if (doubled <= dx) {
            error += dx;
            y += step_y;
        }
    }
}

void PixelCanvas::present()
{
    lv_obj_invalidate(canvas_);
}

} // namespace app
