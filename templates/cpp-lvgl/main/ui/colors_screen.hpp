/*
 * SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
 *
 * SPDX-License-Identifier: MIT
 */

#pragma once

// Demo 1, color rendering: a spinning RGB triangle and an HSV color wheel,
// computed pixel by pixel every frame into an LVGL canvas.

#include "app_ui.hpp"
#include "pixel_canvas.hpp"

#include <array>

namespace app {

class ColorsScreen final : public Screen
{
public:
    explicit ColorsScreen(lv_obj_t *parent);

    std::string title() const override;
    Action handle_key(const key_item &key) override;

protected:
    void on_show() override;
    void on_frame() override;

private:
    enum class Scene { Triangle, Wheel };

    void draw();

    PixelCanvas canvas_;
    std::array<uint16_t, kContentHeight> backdrop_{};  // one color per row
    Scene scene_ = Scene::Triangle;
    float angle_ = 0.0f;
    bool spinning_ = true;
};

} // namespace app
