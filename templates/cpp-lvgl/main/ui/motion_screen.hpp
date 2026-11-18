/*
 * SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
 *
 * SPDX-License-Identifier: MIT
 */

#pragma once

// Demo 2, interactive rendering: push a glowing ball around. It keeps its
// momentum, leaves a trail and throws sparks when it bounces off the walls.

#include "app_ui.hpp"
#include "pixel_canvas.hpp"

#include <cstdint>
#include <deque>
#include <vector>

namespace app {

class MotionScreen final : public Screen
{
public:
    explicit MotionScreen(lv_obj_t *parent);

    std::string title() const override { return "Motion"; }
    Action handle_key(const key_item &key) override;

protected:
    void on_frame() override;

private:
    struct Point
    {
        float x;
        float y;
    };

    struct Spark
    {
        float x;
        float y;
        float vx;
        float vy;
        uint32_t life;
    };

    float next_random();
    void burst(float x, float y);
    void tick();
    void draw();

    PixelCanvas canvas_;
    float x_;
    float y_;
    float vx_ = 0.0f;
    float vy_ = 0.0f;
    std::deque<Point> trail_;
    std::vector<Spark> sparks_;
    size_t color_ = 0;
    uint32_t random_ = 0x2545F491;  // xorshift state, so the sparks need no dependencies
};

} // namespace app
