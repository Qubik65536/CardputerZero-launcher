/*
 * SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
 *
 * SPDX-License-Identifier: MIT
 */

#include "repl_screen.hpp"

#include "input_keys.h"

#include <algorithm>

namespace app {

namespace {

const lv_font_t *const kFont = &lv_font_montserrat_14;
constexpr int kLeft = 4;
constexpr int kTop = 2;
constexpr int kLineHeight = 16;  // lv_font_montserrat_14's line height
constexpr int kTextWidth = kContentWidth - 2 * kLeft;
constexpr int kCursorWidth = 7;
constexpr size_t kMaxInput = 120;
constexpr size_t kMaxScrollback = 200;
const char *const kPrompt = "> ";
const char *const kHelp[] = {
    "numbers, + - * / % ^ ( )",
    "x = 6 * 7   ans   abs(x) min(a,b) max",
    "commands: help  vars  clear",
    "UP/DOWN history  TAB next  ESC home",
};

// Width of `text` in pixels as a label draws it (the text is ASCII).
int text_width(const std::string &text)
{
    int width = 0;
    for (size_t index = 0; index < text.size(); ++index) {
        const uint32_t next = index + 1 < text.size() ? static_cast<unsigned char>(text[index + 1]) : 0;
        width += lv_font_get_glyph_width(kFont, static_cast<unsigned char>(text[index]), next);
    }
    return width;
}

// The longest end of `text` that fits in `room` pixels.
std::string tail_that_fits(const std::string &text, int room)
{
    size_t start = text.size();
    while (start > 0 && text_width(text.substr(start - 1)) <= room) --start;
    return text.substr(start);
}

std::string trim(const std::string &text)
{
    const size_t first = text.find_first_not_of(" \t");
    if (first == std::string::npos) return {};
    const size_t last = text.find_last_not_of(" \t");
    return text.substr(first, last - first + 1);
}

} // namespace

// Add output, wrapped to the screen width.
void ReplScreen::print(const std::string &text, uint32_t color)
{
    std::string line;
    for (char character : text) {
        if (!line.empty() && text_width(line + character) > kTextWidth) {
            scrollback_.push_back({line, color});
            line.clear();
        }
        line += character;
    }
    scrollback_.push_back({line, color});
    if (scrollback_.size() > kMaxScrollback)
        scrollback_.erase(scrollback_.begin(), scrollback_.end() - kMaxScrollback);
}

void ReplScreen::submit()
{
    const std::string line = input_;
    input_.clear();
    print(kPrompt + line, kTextColor);
    const std::string command = trim(line);
    if (command.empty()) return;
    if (history_.empty() || history_.back() != command) history_.push_back(command);
    history_index_ = history_.size();

    if (command == "help") {
        for (const char *help : kHelp) print(help, kMutedColor);
    } else if (command == "clear") {
        scrollback_.clear();
    } else if (command == "vars") {
        if (calculator_.variables().empty()) print("no variables yet", kMutedColor);
        for (const auto &variable : calculator_.variables())
            print(variable.first + " = " + std::to_string(variable.second), kLanguageColor);
    } else {
        const CalcResult result = calculator_.run(command);
        if (result.ok) print(result.text, kLanguageColor);
        else print("error: " + result.text, kErrorColor);
    }
}

// Step through earlier lines: -1 = older, +1 = newer.
void ReplScreen::recall(int step)
{
    const long index = static_cast<long>(history_index_) + step;
    if (index < 0 || index > static_cast<long>(history_.size())) return;
    history_index_ = static_cast<size_t>(index);
    input_ = history_index_ < history_.size() ? history_[history_index_] : std::string();
}

void ReplScreen::refresh()
{
    const size_t visible = std::min(scrollback_.size(), line_labels_.size());
    const size_t first = scrollback_.size() - visible;
    for (size_t row = 0; row < line_labels_.size(); ++row) {
        lv_obj_t *label = line_labels_[row];
        if (row >= visible) {
            lv_obj_add_flag(label, LV_OBJ_FLAG_HIDDEN);
            continue;
        }
        const Line &line = scrollback_[first + row];
        lv_label_set_text(label, line.text.c_str());
        lv_obj_set_style_text_color(label, lv_color_hex(line.color), 0);
        lv_obj_remove_flag(label, LV_OBJ_FLAG_HIDDEN);
    }

    // The input line sits under the output; long input scrolls to keep the end visible.
    const int y = kTop + static_cast<int>(visible) * kLineHeight;
    const int prompt_width = text_width(kPrompt);
    const std::string shown = tail_that_fits(input_, kTextWidth - prompt_width - kCursorWidth - 1);
    lv_label_set_text(input_label_, shown.c_str());
    lv_obj_set_pos(prompt_label_, kLeft, y);
    lv_obj_set_pos(input_label_, kLeft + prompt_width, y);
    lv_obj_set_pos(cursor_, kLeft + prompt_width + text_width(shown) + 1, y + 2);
}

ReplScreen::ReplScreen(lv_obj_t *parent) : Screen(parent)
{
    for (size_t row = 0; row < line_labels_.size(); ++row) {
        line_labels_[row] = make_label(root(), "", kFont, kTextColor);
        lv_obj_set_pos(line_labels_[row], kLeft, kTop + static_cast<int>(row) * kLineHeight);
    }
    prompt_label_ = make_label(root(), kPrompt, kFont, kLanguageColor);
    input_label_ = make_label(root(), "", kFont, kTextColor);
    cursor_ = make_panel(root(), 0, 0, kCursorWidth, kLineHeight - 4, kLanguageColor, LV_OPA_COVER);
    make_hint(root(), "UP/DOWN history  TAB next  ESC home");

    print("calc: whole-number calculator", kMutedColor);
    print("type help and press ENTER", kMutedColor);
    refresh();
}

void ReplScreen::on_show()
{
    // F/X/Z/C type letters here instead of acting as arrows.
    cp0_keyboard_set_input_context(KBD_INPUT_CONTEXT_TEXT);
}

void ReplScreen::on_hide()
{
    cp0_keyboard_set_input_context(KBD_INPUT_CONTEXT_NAVIGATION);
}

Action ReplScreen::handle_key(const key_item &key)
{
    switch (key.key_code) {
    case KEY_ESC: return Action::home();
    case KEY_TAB: return Action::next();
    case KEY_ENTER: submit(); break;
    case KEY_BACKSPACE:
        if (!input_.empty()) input_.pop_back();
        break;
    // Only the real arrow keys: F/X/Z/C are letters here.
    case KEY_UP: recall(-1); break;
    case KEY_DOWN: recall(1); break;
    default:
        if (const char *text = typed_text(key)) {
            if (input_.size() < kMaxInput) input_ += text;
        }
        break;
    }
    refresh();
    return Action::stay();
}

} // namespace app
