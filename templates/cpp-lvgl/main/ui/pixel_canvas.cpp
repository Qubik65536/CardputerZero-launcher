/*
 * SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
 *
 * SPDX-License-Identifier: MIT
 */

#include "pixel_canvas.hpp"

#include <algorithm>

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

void PixelCanvas::present()
{
    lv_obj_invalidate(canvas_);
}

} // namespace app
