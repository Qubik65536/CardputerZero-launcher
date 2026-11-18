/*
 * SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
 *
 * SPDX-License-Identifier: MIT
 */

#include "motion_screen.hpp"

#include "input_keys.h"

#include <algorithm>
#include <array>
#include <cmath>

namespace app {

namespace {

constexpr float kRadius = 9.0f;
constexpr float kPush = 1.2f;       // speed added per key press, pixels per frame
constexpr float kFriction = 0.99f;  // speed kept each frame
constexpr float kBounce = 0.85f;    // speed kept when bouncing
constexpr size_t kTrailLength = 14;
constexpr int kSparksPerBounce = 10;
constexpr uint32_t kSparkLife = 30;  // frames
constexpr uint16_t kGrid = rgb565(0x242C36);
constexpr std::array<uint16_t, 4> kColors = {rgb565(kLanguageColor), rgb565(0x4FC3F7), rgb565(0x81C784),
                                             rgb565(0xF06292)};

// The area the ball moves in: between the key line at the top and the hint line.
constexpr float kLeft = 0.0f;
constexpr float kRight = static_cast<float>(kContentWidth);
constexpr float kTop = 18.0f;  // below the "TAB next  ESC home" line
constexpr float kBottom = static_cast<float>(kHintTop - 2);

} // namespace

MotionScreen::MotionScreen(lv_obj_t *parent)
    : Screen(parent), canvas_(root(), kContentWidth, kContentHeight), x_((kLeft + kRight) / 2.0f),
      y_((kTop + kBottom) / 2.0f)
{
    // Widgets created after the canvas are drawn on top of it.
    make_demo_keys(root());
    make_hint(root(), "F/X/Z/C push  ENTER color  SPACE stop");
    animate();
}

// A number from -1 to 1 (xorshift).
float MotionScreen::next_random()
{
    random_ ^= random_ << 13;
    random_ ^= random_ >> 17;
    random_ ^= random_ << 5;
    return static_cast<float>(random_ % 2001) / 1000.0f - 1.0f;
}

void MotionScreen::burst(float x, float y)
{
    for (int index = 0; index < kSparksPerBounce; ++index) {
        const float vx = next_random() * 2.5f;
        const float vy = next_random() * 2.5f - 1.0f;
        sparks_.push_back({x, y, vx, vy, kSparkLife});
    }
}

// Advance one frame: move, bounce, age the trail and the sparks.
void MotionScreen::tick()
{
    x_ += vx_;
    y_ += vy_;
    vx_ *= kFriction;
    vy_ *= kFriction;
    if (x_ < kLeft + kRadius || x_ > kRight - kRadius) {
        x_ = std::clamp(x_, kLeft + kRadius, kRight - kRadius);
        vx_ = -vx_ * kBounce;
        if (std::fabs(vx_) > 0.6f) burst(vx_ > 0.0f ? x_ - kRadius : x_ + kRadius, y_);
    }
    if (y_ < kTop + kRadius || y_ > kBottom - kRadius) {
        y_ = std::clamp(y_, kTop + kRadius, kBottom - kRadius);
        vy_ = -vy_ * kBounce;
        if (std::fabs(vy_) > 0.6f) burst(x_, vy_ > 0.0f ? y_ - kRadius : y_ + kRadius);
    }
    trail_.push_front({x_, y_});
    if (trail_.size() > kTrailLength) trail_.pop_back();
    for (Spark &spark : sparks_) {
        spark.x += spark.vx;
        spark.y += spark.vy;
        spark.vy += 0.08f;  // gravity
        spark.life -= 1;
    }
    sparks_.erase(std::remove_if(sparks_.begin(), sparks_.end(), [](const Spark &spark) { return spark.life == 0; }),
                  sparks_.end());
}

void MotionScreen::draw()
{
    const uint16_t color = kColors[color_];
    canvas_.clear(rgb565(kBackgroundColor));
    for (int y = static_cast<int>(kTop) + 8; y < static_cast<int>(kBottom); y += 16) {
        for (int x = 8; x < static_cast<int>(kRight); x += 16) canvas_.set_pixel(x, y, kGrid);
    }
    // Oldest trail first, so newer, brighter circles land on top.
    const float length = static_cast<float>(trail_.size());
    for (size_t age = trail_.size(); age-- > 0;) {
        const float fade = 1.0f - static_cast<float>(age) / length;
        canvas_.fill_circle(static_cast<int>(trail_[age].x), static_cast<int>(trail_[age].y),
                            static_cast<int>(kRadius * (0.3f + 0.6f * fade)), color,
                            static_cast<uint8_t>(90.0f * fade));
    }
    for (const Spark &spark : sparks_) {
        const auto alpha = static_cast<uint8_t>(spark.life * 255 / kSparkLife);
        canvas_.fill_circle(static_cast<int>(spark.x), static_cast<int>(spark.y), 1, color, alpha);
    }
    const int x = static_cast<int>(x_);
    const int y = static_cast<int>(y_);
    const int radius = static_cast<int>(kRadius);
    canvas_.fill_circle(x, y, radius + 6, color, 35);  // glow
    canvas_.fill_circle(x, y, radius + 3, color, 70);
    canvas_.fill_circle(x, y, radius, color, 255);
    canvas_.fill_circle(x - 3, y - 3, 3, rgb565(0xFFFFFF), 140);  // highlight
    canvas_.present();
}

void MotionScreen::on_frame()
{
    tick();
    draw();
}

Action MotionScreen::handle_key(const key_item &key)
{
    switch (direction(key.key_code)) {
    case Direction::Left: vx_ -= kPush; break;
    case Direction::Right: vx_ += kPush; break;
    case Direction::Up: vy_ -= kPush; break;
    case Direction::Down: vy_ += kPush; break;
    case Direction::None:
        switch (key.key_code) {
        case KEY_ENTER: color_ = (color_ + 1) % kColors.size(); break;
        case KEY_SPACE: vx_ = vy_ = 0.0f; break;
        case KEY_TAB: return Action::next();
        case KEY_ESC: return Action::home();
        default: break;
        }
        break;
    }
    return Action::stay();
}

} // namespace app
