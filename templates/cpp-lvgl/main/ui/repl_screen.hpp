/*
 * SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
 *
 * SPDX-License-Identifier: MIT
 */

#pragma once

// Demo 3, a terminal-style tool: a read-eval-print loop for the `calc`
// language (calc.hpp). Type a line, ENTER runs it; the screen scrolls like a
// terminal.

#include "app_ui.hpp"
#include "calc.hpp"

#include <array>
#include <cstdint>
#include <string>
#include <vector>

namespace app {

class ReplScreen final : public Screen
{
public:
    explicit ReplScreen(lv_obj_t *parent);

    std::string title() const override { return "REPL"; }
    Action handle_key(const key_item &key) override;

protected:
    void on_show() override;
    void on_hide() override;

private:
    // Text rows above the hint line; the last one is the input line.
    static constexpr size_t kRows = 8;

    struct Line
    {
        std::string text;
        uint32_t color;
    };

    void print(const std::string &text, uint32_t color);
    void submit();
    void recall(int step);
    void refresh();

    Calculator calculator_;
    std::vector<Line> scrollback_;
    std::string input_;
    std::vector<std::string> history_;
    size_t history_index_ = 0;  // == history_.size() while editing a new line

    std::array<lv_obj_t *, kRows - 1> line_labels_{};
    lv_obj_t *prompt_label_ = nullptr;
    lv_obj_t *input_label_ = nullptr;
    lv_obj_t *cursor_ = nullptr;
};

} // namespace app
