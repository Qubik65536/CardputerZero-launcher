/*
 * SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
 *
 * SPDX-License-Identifier: MIT
 */

#pragma once

// `calc`, the tiny language behind the REPL demo: whole numbers, + - * / % ^,
// parentheses, variables (`x = 6 * 7`, `ans` is the last result) and the
// functions abs, min and max. Pure C++17, no LVGL.

#include <cstdint>
#include <map>
#include <string>

struct CalcResult
{
    bool ok = false;
    std::string text;  // the value to show (`3`, `x = 3`), or the error message
};

// The interpreter: variables live as long as it does.
class Calculator
{
public:
    // Run one line: an expression (`1 + 2`) or an assignment (`x = 1 + 2`).
    CalcResult run(const std::string &line);

    // Every variable and its value, in name order.
    const std::map<std::string, int64_t> &variables() const { return variables_; }

private:
    std::map<std::string, int64_t> variables_;
};
