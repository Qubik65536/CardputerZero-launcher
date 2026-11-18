/*
 * SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
 *
 * SPDX-License-Identifier: MIT
 */

// The host hooks the emulator overrides to show external apps in its window.

#include "../src/sdl/sdl_external_app_runner.hpp"

#include <cassert>
#include <cstdlib>

namespace {
const char *const kExtraEnv[] = {"CARDPUTER_FB=/tmp/hook-fb", "HOOK_TEST_REPLACED=new", nullptr};
bool provide_env = true;
int begin_calls = 0;
int begin_pid = 0;
int tick_calls = 0;
int end_calls = 0;
int ticks_at_end = -1;
}

extern "C" const char *const *cp0_sdl_external_app_env(void)
{
    return provide_env ? kExtraEnv : nullptr;
}

extern "C" void cp0_sdl_external_app_begin(int pid)
{
    ++begin_calls;
    begin_pid = pid;
}

extern "C" int cp0_sdl_external_app_tick(void)
{
    ++tick_calls;
    return 5;
}

extern "C" void cp0_sdl_external_app_end(void)
{
    ++end_calls;
    ticks_at_end = tick_calls;
}

int main()
{
    setenv("HOOK_TEST_REPLACED", "old", 1);
    setenv("HOOK_TEST_KEPT", "kept", 1);

    // Extra variables reach the app, replace same-named ones and keep the rest.
    assert(sdl_external_app_runner::run(
               "test \"$CARDPUTER_FB\" = /tmp/hook-fb && test \"$HOOK_TEST_REPLACED\" = new && "
               "test \"$HOOK_TEST_KEPT\" = kept && sleep 0.2 && exit 4") == 4);
    assert(begin_calls == 1);
    assert(begin_pid > 0);
    assert(end_calls == 1);
    // A 5 ms tick over a 200 ms app runs many times, before end().
    assert(tick_calls >= 10);
    assert(ticks_at_end == tick_calls);

    // Without extra variables the parent's environment is used unchanged.
    provide_env = false;
    assert(sdl_external_app_runner::run("test -z \"$CARDPUTER_FB\" && "
                                        "test \"$HOOK_TEST_REPLACED\" = old") == 0);
    assert(begin_calls == 2);
    assert(end_calls == 2);
}
