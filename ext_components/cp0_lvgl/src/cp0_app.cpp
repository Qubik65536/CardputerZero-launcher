/*
 * SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
 *
 * SPDX-License-Identifier: MIT
 */

// cp0_app: the C entry point in cp0_app.h, a thin wrapper over
// cp0_lvgl_run_app<Page>() for apps written in other languages.

#include "cp0_app.h"

#include "cp0_lvgl_app_runner.hpp"
#include "cp0_lvgl_filesystem.hpp"
#include "keyboard_input.h"

#include <cstdio>
#include <cstring>
#include <string>

namespace {

struct CAppState
{
    std::string title;
    cp0_app_setup_fn setup = nullptr;
    cp0_app_key_fn on_key = nullptr;
    void *user_data = nullptr;
    bool quit_requested = false;
};

CAppState g_state;

class CAppPage;
CAppPage *g_page = nullptr;

class CAppPage : public AppPage
{
public:
    CAppPage()
    {
        set_page_title(g_state.title);
        lv_obj_add_event_cb(root_screen_, key_event_cb, LV_EVENT_ALL, nullptr);
        g_page = this;
    }

    ~CAppPage() override { g_page = nullptr; }

    lv_obj_t *content() const { return ui_APP_Container; }
    lv_obj_t *root() const { return root_screen_; }
    void title(const char *text) { set_page_title(text ? text : ""); }

private:
    // cp0_lvgl delivers every key to the active screen as LV_EVENT_KEYBOARD.
    static void key_event_cb(lv_event_t *event)
    {
        if (lv_event_get_code(event) != static_cast<lv_event_code_t>(LV_EVENT_KEYBOARD) || !g_state.on_key) return;
        const auto *item = static_cast<const key_item *>(lv_event_get_param(event));
        if (!item) return;
        cp0_app_key_t key;
        key.code = item->key_code;
        key.state = item->key_state;
        key.mods = item->mods;
        key.text = item->utf8;
        g_state.on_key(&key, g_state.user_data);
    }
};

} // namespace

extern "C" int cp0_app_run(const char *title, cp0_app_setup_fn setup, cp0_app_key_fn on_key, void *user_data)
{
    g_state = CAppState{};
    g_state.title = title ? title : "";
    g_state.setup = setup;
    g_state.on_key = on_key;
    g_state.user_data = user_data;

    Cp0LvglAppHooks hooks;
    hooks.after_page_init = [](AppPageRoot &) {
        if (g_page && g_state.setup) g_state.setup(g_page->content(), g_state.user_data);
    };
    hooks.should_quit = [] { return g_state.quit_requested; };
    return cp0_lvgl_run_app<CAppPage>(std::move(hooks));
}

extern "C" void cp0_app_quit(void)
{
    g_state.quit_requested = true;
    cp0_lvgl_wake();
}

extern "C" void cp0_app_set_title(const char *title)
{
    if (g_page) g_page->title(title);
}

extern "C" lv_obj_t *cp0_app_content(void)
{
    return g_page ? g_page->content() : nullptr;
}

extern "C" lv_obj_t *cp0_app_screen(void)
{
    return g_page ? g_page->root() : nullptr;
}

extern "C" void cp0_app_set_text_input(int enabled)
{
    cp0_keyboard_set_input_context(enabled ? KBD_INPUT_CONTEXT_TEXT : KBD_INPUT_CONTEXT_NAVIGATION);
}

extern "C" void cp0_app_set_keypad_intercept(int enabled)
{
    cp0_keyboard_set_lvgl_keypad_intercept(enabled ? 1 : 0);
}

extern "C" size_t cp0_app_file_path(const char *name, char *out, size_t size)
{
    const std::string path = cp0_file_path(name ? name : "");
    if (out && size > 0) std::snprintf(out, size, "%s", path.c_str());
    return path.size();
}
