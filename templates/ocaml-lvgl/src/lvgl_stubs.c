/*
 * SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
 *
 * SPDX-License-Identifier: MIT
 */

/*
 * The C half of lvgl.ml: one small function per LVGL or cp0_app call the app
 * makes. Each `external` in lvgl.ml names one of these functions.
 *
 * Values
 *   Pointers (lv_obj_t *, lv_group_t *, lv_timer_t *, const lv_font_t *,
 *   lv_event_t *) cross into OCaml as tagged integers: the address with its
 *   lowest bit set. LVGL's structures are at least 4-byte aligned, so that bit
 *   is always free, and the result is an ordinary OCaml int: the garbage
 *   collector ignores it (OCaml 5 forbids naked pointers into C memory) and no
 *   boxing is needed. lvgl.ml declares the types abstract and [@@immediate].
 *   Colors are 0xRRGGBB ints turned into lv_color_t here with lv_color_hex;
 *   selectors, flags, states and event codes are ints (their values are
 *   checked against the LVGL headers at the bottom of this file).
 *
 * Callbacks
 *   LVGL calls C function pointers; the app wants OCaml closures. Each closure
 *   is stored in a malloc'ed cell registered as a GC root
 *   (caml_register_generational_global_root), so the collector keeps it alive
 *   and updates the cell when it moves the closure. The cell is the C
 *   callback's user_data; a trampoline calls the closure through it:
 *     - object events: the cell is freed by a second handler on LV_EVENT_DELETE;
 *     - timers: Timer.delete frees it;
 *     - a group's focus callback: stored in the group's user_data.
 *   Exceptions must not unwind through LVGL's C frames: lvgl.ml wraps every
 *   closure in Lvgl.guard, which reports an uncaught exception and exits with
 *   status 2 like OCaml does at top level, and the trampolines use
 *   caml_callback_exn as a backstop.
 *   When the app's content area is deleted (the app is quitting: the page is
 *   torn down, which deletes every widget and moves group focus as it goes),
 *   callbacks stop reaching OCaml, so no app code runs against half-deleted
 *   widgets.
 *
 * GC safety
 *   Arguments that are tagged pointers or ints need no protection, even if
 *   the call runs OCaml callbacks. Stubs that take strings or closures use
 *   CAMLparam, and copy a string first when LVGL could call back into OCaml
 *   while still reading it (lv_textarea_add_text sends events).
 *
 * Calling more of LVGL
 *   1. Find the function in SDK/github_source/lvgl/lvgl_9_5/lvgl/src (e.g.
 *      widgets/bar/lv_bar.h: void lv_bar_set_value(lv_obj_t * obj, int32_t value, lv_anim_enable_t anim)).
 *   2. Add a stub here: value arguments in, Obj_val/Int_val/Bool_val/String_val
 *      to convert, Val_unit/Val_int/Val_pointer out. Static inline functions and
 *      macros from the headers (lv_obj_set_style_pad_hor, lv_color_hex, ...)
 *      work here too: this is C.
 *   3. Declare it in lvgl.ml: external set_value : obj -> int -> anim:bool -> unit = "ml_lv_bar_set_value"
 *      (a stub with more than 5 arguments needs a second, bytecode version; see the OCaml manual).
 */

#include <caml/alloc.h>
#include <caml/bigarray.h>
#include <caml/callback.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/printexc.h>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "cp0_app.h"
#include "lvgl/lvgl.h"

/* ---- Pointers as tagged ints -------------------------------------------
 * (OCaml >= 5.1's own Val_ptr/Ptr_val use the same encoding.) */

static inline value Val_pointer(const void *pointer)
{
    return (value)((uintptr_t)pointer | 1);
}

static inline void *Pointer_val(value v)
{
    return (void *)((uintptr_t)v & ~(uintptr_t)1);
}

#define Obj_val(v) ((lv_obj_t *)Pointer_val(v))
#define Group_val(v) ((lv_group_t *)Pointer_val(v))
#define Timer_val(v) ((lv_timer_t *)Pointer_val(v))
#define Font_val(v) ((const lv_font_t *)Pointer_val(v))
#define Event_val(v) ((lv_event_t *)Pointer_val(v))
#define I32_val(v) ((int32_t)Long_val(v))
#define U32_val(v) ((uint32_t)Long_val(v))

/* ---- Closures kept alive for C ----------------------------------------- */

/* Off before the app starts and from the moment it is torn down. */
static int ml_callbacks_enabled = 0;

static value *ml_closure_new(value closure)
{
    value *cell = caml_stat_alloc(sizeof *cell);
    *cell = closure;
    caml_register_generational_global_root(cell);
    return cell;
}

static void ml_closure_free(value *cell)
{
    caml_remove_generational_global_root(cell);
    caml_stat_free(cell);
}

static void ml_closure_call(const value *cell, value argument)
{
    if (!ml_callbacks_enabled) return;
    const value result = caml_callback_exn(*cell, argument);
    if (Is_exception_result(result)) {
        /* Lvgl.guard already handles exceptions in app code; this is the backstop. */
        char *message = caml_format_exception(Extract_exception(result));
        fprintf(stderr, "Fatal error: exception %s\n", message);
        exit(2);
    }
}

/* ---- cp0_app ------------------------------------------------------------ */

static value ml_setup_closure = Val_unit;
static value ml_key_closure = Val_unit;

static void ml_app_content_deleted(lv_event_t *event)
{
    (void)event;
    ml_callbacks_enabled = 0;
}

static void ml_app_setup(lv_obj_t *content, void *user_data)
{
    (void)user_data;
    ml_callbacks_enabled = 1;
    lv_obj_add_event_cb(content, ml_app_content_deleted, LV_EVENT_DELETE, NULL);
    ml_closure_call(&ml_setup_closure, Val_pointer(content));
}

/* The key becomes an OCaml record { code; state; mods; text } (Lvgl.App.key). */
static void ml_app_on_key(const cp0_app_key_t *key, void *user_data)
{
    CAMLparam0();
    CAMLlocal2(text, record);
    (void)user_data;
    if (!ml_callbacks_enabled) CAMLreturn0;
    /* Lvgl.App.key_state: Released | Pressed | Repeated */
    const int state = key->state == CP0_APP_KEY_RELEASED ? 0 : key->state == CP0_APP_KEY_REPEATED ? 2 : 1;
    text = caml_copy_string(key->text ? key->text : "");
    record = caml_alloc_tuple(4);
    Store_field(record, 0, Val_long(key->code));
    Store_field(record, 1, Val_int(state));
    Store_field(record, 2, Val_long(key->mods));
    Store_field(record, 3, text);
    ml_closure_call(&ml_key_closure, record);
    CAMLreturn0;
}

value ml_cp0_app_run(value title, value setup, value on_key)
{
    CAMLparam3(title, setup, on_key);
    char *c_title = caml_stat_strdup(String_val(title));
    ml_setup_closure = setup;
    ml_key_closure = on_key;
    caml_register_generational_global_root(&ml_setup_closure);
    caml_register_generational_global_root(&ml_key_closure);
    const int status = cp0_app_run(c_title, ml_app_setup, ml_app_on_key, NULL);
    ml_callbacks_enabled = 0;
    caml_remove_generational_global_root(&ml_setup_closure);
    caml_remove_generational_global_root(&ml_key_closure);
    caml_stat_free(c_title);
    CAMLreturn(Val_int(status));
}

value ml_cp0_app_quit(value unit)
{
    (void)unit;
    cp0_app_quit();
    return Val_unit;
}

value ml_cp0_app_set_title(value title)
{
    cp0_app_set_title(String_val(title));
    return Val_unit;
}

value ml_cp0_app_content(value unit)
{
    (void)unit;
    return Val_pointer(cp0_app_content());
}

value ml_cp0_app_screen(value unit)
{
    (void)unit;
    return Val_pointer(cp0_app_screen());
}

value ml_cp0_app_set_text_input(value enabled)
{
    cp0_app_set_text_input(Bool_val(enabled));
    return Val_unit;
}

value ml_cp0_app_set_keypad_intercept(value enabled)
{
    cp0_app_set_keypad_intercept(Bool_val(enabled));
    return Val_unit;
}

value ml_cp0_app_file_path(value name)
{
    CAMLparam1(name);
    CAMLlocal1(result);
    const size_t length = cp0_app_file_path(String_val(name), NULL, 0);
    char *path = caml_stat_alloc(length + 1);
    cp0_app_file_path(String_val(name), path, length + 1);
    result = caml_copy_string(path);
    caml_stat_free(path);
    CAMLreturn(result);
}

/* ---- Objects (lv_obj_*) ------------------------------------------------- */

value ml_lv_obj_create(value parent)
{
    return Val_pointer(lv_obj_create(Obj_val(parent)));
}

value ml_lv_obj_remove_style_all(value obj)
{
    lv_obj_remove_style_all(Obj_val(obj));
    return Val_unit;
}

value ml_lv_obj_set_pos(value obj, value x, value y)
{
    lv_obj_set_pos(Obj_val(obj), I32_val(x), I32_val(y));
    return Val_unit;
}

value ml_lv_obj_set_size(value obj, value width, value height)
{
    lv_obj_set_size(Obj_val(obj), I32_val(width), I32_val(height));
    return Val_unit;
}

value ml_lv_obj_set_width(value obj, value width)
{
    lv_obj_set_width(Obj_val(obj), I32_val(width));
    return Val_unit;
}

value ml_lv_obj_align(value obj, value align, value x, value y)
{
    lv_obj_align(Obj_val(obj), (lv_align_t)Int_val(align), I32_val(x), I32_val(y));
    return Val_unit;
}

value ml_lv_obj_center(value obj)
{
    lv_obj_center(Obj_val(obj));
    return Val_unit;
}

value ml_lv_obj_add_flag(value obj, value flag)
{
    lv_obj_add_flag(Obj_val(obj), (lv_obj_flag_t)U32_val(flag));
    return Val_unit;
}

value ml_lv_obj_remove_flag(value obj, value flag)
{
    lv_obj_remove_flag(Obj_val(obj), (lv_obj_flag_t)U32_val(flag));
    return Val_unit;
}

value ml_lv_obj_has_flag(value obj, value flag)
{
    return Val_bool(lv_obj_has_flag(Obj_val(obj), (lv_obj_flag_t)U32_val(flag)));
}

value ml_lv_obj_add_state(value obj, value state)
{
    lv_obj_add_state(Obj_val(obj), (lv_state_t)U32_val(state));
    return Val_unit;
}

value ml_lv_obj_remove_state(value obj, value state)
{
    lv_obj_remove_state(Obj_val(obj), (lv_state_t)U32_val(state));
    return Val_unit;
}

value ml_lv_obj_has_state(value obj, value state)
{
    return Val_bool(lv_obj_has_state(Obj_val(obj), (lv_state_t)U32_val(state)));
}

value ml_lv_obj_set_state(value obj, value state, value enabled)
{
    lv_obj_set_state(Obj_val(obj), (lv_state_t)U32_val(state), Bool_val(enabled));
    return Val_unit;
}

value ml_lv_obj_invalidate(value obj)
{
    lv_obj_invalidate(Obj_val(obj));
    return Val_unit;
}

/* ---- Events ------------------------------------------------------------- */

static void ml_event_trampoline(lv_event_t *event)
{
    ml_closure_call(lv_event_get_user_data(event), Val_pointer(event));
}

static void ml_event_free_closure(lv_event_t *event)
{
    ml_closure_free(lv_event_get_user_data(event));
}

value ml_lv_obj_add_event_cb(value obj, value filter, value closure)
{
    CAMLparam1(closure);
    value *cell = ml_closure_new(closure);
    lv_obj_add_event_cb(Obj_val(obj), ml_event_trampoline, (lv_event_code_t)Int_val(filter), cell);
    /* Added second, so it runs after the app's own LV_EVENT_DELETE handler. */
    lv_obj_add_event_cb(Obj_val(obj), ml_event_free_closure, LV_EVENT_DELETE, cell);
    CAMLreturn(Val_unit);
}

value ml_lv_obj_send_event(value obj, value code)
{
    lv_obj_send_event(Obj_val(obj), (lv_event_code_t)Int_val(code), NULL);
    return Val_unit;
}

value ml_lv_event_get_code(value event)
{
    return Val_int(lv_event_get_code(Event_val(event)));
}

value ml_lv_event_get_target(value event)
{
    return Val_pointer(lv_event_get_target_obj(Event_val(event)));
}

/* ---- Styles (lv_obj_set_style_*) ----------------------------------------
 * Every setter is (obj, value, selector); the macros below write them. Add a
 * property with one line, then one line in lvgl.ml's Obj module. */

#define ML_STYLE_INT(property)                                                                        \
    value ml_lv_obj_set_style_##property(value obj, value v, value selector)                          \
    {                                                                                                 \
        lv_obj_set_style_##property(Obj_val(obj), I32_val(v), (lv_style_selector_t)U32_val(selector)); \
        return Val_unit;                                                                              \
    }

#define ML_STYLE_COLOR(property)                                                                      \
    value ml_lv_obj_set_style_##property(value obj, value hex, value selector)                        \
    {                                                                                                 \
        lv_obj_set_style_##property(Obj_val(obj), lv_color_hex(U32_val(hex)),                      \
                                    (lv_style_selector_t)U32_val(selector));                       \
        return Val_unit;                                                                              \
    }

ML_STYLE_COLOR(bg_color)
ML_STYLE_INT(bg_opa)
ML_STYLE_INT(border_width)
ML_STYLE_COLOR(border_color)
ML_STYLE_COLOR(text_color)
ML_STYLE_INT(text_opa)
ML_STYLE_INT(text_align)
ML_STYLE_INT(pad_all)
ML_STYLE_INT(pad_hor)
ML_STYLE_INT(pad_ver)
ML_STYLE_INT(pad_right)
ML_STYLE_INT(anim_duration)
ML_STYLE_COLOR(outline_color)
ML_STYLE_INT(outline_width)
ML_STYLE_INT(outline_pad)

value ml_lv_obj_set_style_text_font(value obj, value font, value selector)
{
    lv_obj_set_style_text_font(Obj_val(obj), Font_val(font), (lv_style_selector_t)U32_val(selector));
    return Val_unit;
}

/* ---- Fonts -------------------------------------------------------------- */

value ml_lv_font_montserrat_12(value unit)
{
    (void)unit;
    return Val_pointer(&lv_font_montserrat_12);
}

value ml_lv_font_montserrat_14(value unit)
{
    (void)unit;
    return Val_pointer(&lv_font_montserrat_14);
}

value ml_lv_font_montserrat_28(value unit)
{
    (void)unit;
    return Val_pointer(&lv_font_montserrat_28);
}

value ml_lv_font_get_glyph_width(value font, value letter, value next)
{
    return Val_int(lv_font_get_glyph_width(Font_val(font), U32_val(letter), U32_val(next)));
}

/* ---- Widgets ------------------------------------------------------------ */

value ml_lv_label_create(value parent)
{
    return Val_pointer(lv_label_create(Obj_val(parent)));
}

value ml_lv_label_set_text(value label, value text)
{
    lv_label_set_text(Obj_val(label), String_val(text)); /* LVGL copies the text */
    return Val_unit;
}

value ml_lv_image_create(value parent)
{
    return Val_pointer(lv_image_create(Obj_val(parent)));
}

value ml_lv_image_set_src_file(value image, value path)
{
    lv_image_set_src(Obj_val(image), String_val(path)); /* a file path; LVGL copies it */
    return Val_unit;
}

value ml_lv_canvas_create(value parent)
{
    return Val_pointer(lv_canvas_create(Obj_val(parent)));
}

/* The pixels stay in the Bigarray (outside the OCaml heap, so they never
 * move); the OCaml side must keep the Bigarray alive as long as the canvas. */
value ml_lv_canvas_set_buffer_rgb565(value canvas, value pixels, value width, value height)
{
    CAMLparam1(pixels);
    lv_canvas_set_buffer(Obj_val(canvas), Caml_ba_data_val(pixels), I32_val(width), I32_val(height),
                         LV_COLOR_FORMAT_RGB565);
    CAMLreturn(Val_unit);
}

value ml_lv_button_create(value parent)
{
    return Val_pointer(lv_button_create(Obj_val(parent)));
}

value ml_lv_textarea_create(value parent)
{
    return Val_pointer(lv_textarea_create(Obj_val(parent)));
}

value ml_lv_textarea_set_one_line(value textarea, value enabled)
{
    lv_textarea_set_one_line(Obj_val(textarea), Bool_val(enabled));
    return Val_unit;
}

value ml_lv_textarea_set_placeholder_text(value textarea, value text)
{
    lv_textarea_set_placeholder_text(Obj_val(textarea), String_val(text));
    return Val_unit;
}

value ml_lv_textarea_set_max_length(value textarea, value length)
{
    lv_textarea_set_max_length(Obj_val(textarea), U32_val(length));
    return Val_unit;
}

value ml_lv_textarea_get_text(value textarea)
{
    return caml_copy_string(lv_textarea_get_text(Obj_val(textarea)));
}

value ml_lv_textarea_add_text(value textarea, value text)
{
    CAMLparam1(text);
    char *copy = caml_stat_strdup(String_val(text));
    lv_textarea_add_text(Obj_val(textarea), copy);
    caml_stat_free(copy);
    CAMLreturn(Val_unit);
}

value ml_lv_textarea_delete_char(value textarea)
{
    lv_textarea_delete_char(Obj_val(textarea));
    return Val_unit;
}

value ml_lv_slider_create(value parent)
{
    return Val_pointer(lv_slider_create(Obj_val(parent)));
}

value ml_lv_slider_set_range(value slider, value min, value max)
{
    lv_slider_set_range(Obj_val(slider), I32_val(min), I32_val(max));
    return Val_unit;
}

value ml_lv_slider_set_value(value slider, value v, value anim)
{
    lv_slider_set_value(Obj_val(slider), I32_val(v), Bool_val(anim) ? LV_ANIM_ON : LV_ANIM_OFF);
    return Val_unit;
}

value ml_lv_slider_get_value(value slider)
{
    return Val_long(lv_slider_get_value(Obj_val(slider)));
}

value ml_lv_roller_create(value parent)
{
    return Val_pointer(lv_roller_create(Obj_val(parent)));
}

value ml_lv_roller_set_options(value roller, value options, value infinite)
{
    lv_roller_set_options(Obj_val(roller), String_val(options),
                          Bool_val(infinite) ? LV_ROLLER_MODE_INFINITE : LV_ROLLER_MODE_NORMAL);
    return Val_unit;
}

value ml_lv_roller_set_visible_row_count(value roller, value rows)
{
    lv_roller_set_visible_row_count(Obj_val(roller), U32_val(rows));
    return Val_unit;
}

value ml_lv_roller_set_selected(value roller, value index, value anim)
{
    lv_roller_set_selected(Obj_val(roller), U32_val(index), Bool_val(anim) ? LV_ANIM_ON : LV_ANIM_OFF);
    return Val_unit;
}

value ml_lv_roller_get_selected(value roller)
{
    return Val_long(lv_roller_get_selected(Obj_val(roller)));
}

value ml_lv_switch_create(value parent)
{
    return Val_pointer(lv_switch_create(Obj_val(parent)));
}

/* ---- Groups (keyboard focus) -------------------------------------------- */

static void ml_group_focus_trampoline(lv_group_t *group)
{
    ml_closure_call(lv_group_get_user_data(group), Val_pointer(group));
}

value ml_lv_group_create(value unit)
{
    (void)unit;
    return Val_pointer(lv_group_create());
}

value ml_lv_group_delete(value group)
{
    value *cell = lv_group_get_user_data(Group_val(group));
    lv_group_delete(Group_val(group));
    if (cell) ml_closure_free(cell);
    return Val_unit;
}

value ml_lv_group_set_focus_cb(value group, value closure)
{
    CAMLparam1(closure);
    value *old = lv_group_get_user_data(Group_val(group));
    lv_group_set_user_data(Group_val(group), ml_closure_new(closure));
    lv_group_set_focus_cb(Group_val(group), ml_group_focus_trampoline);
    if (old) ml_closure_free(old);
    CAMLreturn(Val_unit);
}

value ml_lv_group_set_wrap(value group, value enabled)
{
    lv_group_set_wrap(Group_val(group), Bool_val(enabled));
    return Val_unit;
}

value ml_lv_group_add_obj(value group, value obj)
{
    lv_group_add_obj(Group_val(group), Obj_val(obj));
    return Val_unit;
}

value ml_lv_group_focus_obj(value obj)
{
    lv_group_focus_obj(Obj_val(obj));
    return Val_unit;
}

value ml_lv_group_focus_next(value group)
{
    lv_group_focus_next(Group_val(group));
    return Val_unit;
}

value ml_lv_group_focus_prev(value group)
{
    lv_group_focus_prev(Group_val(group));
    return Val_unit;
}

value ml_lv_group_get_focused(value group)
{
    return Val_pointer(lv_group_get_focused(Group_val(group)));
}

/* ---- Timers ------------------------------------------------------------- */

static void ml_timer_trampoline(lv_timer_t *timer)
{
    ml_closure_call(lv_timer_get_user_data(timer), Val_pointer(timer));
}

value ml_lv_timer_create(value period, value closure)
{
    CAMLparam1(closure);
    lv_timer_t *timer = lv_timer_create(ml_timer_trampoline, U32_val(period), ml_closure_new(closure));
    CAMLreturn(Val_pointer(timer));
}

value ml_lv_timer_delete(value timer)
{
    value *cell = lv_timer_get_user_data(Timer_val(timer));
    lv_timer_delete(Timer_val(timer));
    ml_closure_free(cell);
    return Val_unit;
}

value ml_lv_timer_pause(value timer)
{
    lv_timer_pause(Timer_val(timer));
    return Val_unit;
}

value ml_lv_timer_resume(value timer)
{
    lv_timer_resume(Timer_val(timer));
    return Val_unit;
}

value ml_lv_timer_reset(value timer)
{
    lv_timer_reset(Timer_val(timer));
    return Val_unit;
}

/* ---- The constants lvgl.ml spells out, checked against LVGL 9.5 ---------- */

_Static_assert(LV_ALIGN_TOP_LEFT == 1 && LV_ALIGN_TOP_MID == 2 && LV_ALIGN_TOP_RIGHT == 3 && LV_ALIGN_CENTER == 9,
               "Lvgl.Align");
_Static_assert(LV_PART_MAIN == 0 && LV_PART_INDICATOR == 0x020000 && LV_PART_KNOB == 0x030000 &&
                   LV_PART_SELECTED == 0x040000 && LV_PART_CURSOR == 0x060000 &&
                   LV_PART_TEXTAREA_PLACEHOLDER == 0x080000,
               "Lvgl.Part");
_Static_assert(LV_STATE_DEFAULT == 0 && LV_STATE_CHECKED == 0x04 && LV_STATE_FOCUSED == 0x08 &&
                   LV_STATE_PRESSED == 0x80,
               "Lvgl.State");
_Static_assert(LV_OBJ_FLAG_HIDDEN == 0x01 && LV_OBJ_FLAG_CLICKABLE == 0x02 && LV_OBJ_FLAG_SCROLLABLE == 0x10,
               "Lvgl.Flag");
_Static_assert(LV_EVENT_ALL == 0 && LV_EVENT_PRESSED == 1 && LV_EVENT_CLICKED == 10 && LV_EVENT_RELEASED == 11 &&
                   LV_EVENT_KEY == 17 && LV_EVENT_FOCUSED == 19 && LV_EVENT_DEFOCUSED == 20 &&
                   LV_EVENT_VALUE_CHANGED == 35 && LV_EVENT_DELETE == 42,
               "Lvgl.Event");
_Static_assert(LV_OPA_TRANSP == 0 && LV_OPA_COVER == 255, "Lvgl.Opa");
_Static_assert(LV_TEXT_ALIGN_LEFT == 1 && LV_TEXT_ALIGN_CENTER == 2 && LV_TEXT_ALIGN_RIGHT == 3, "Lvgl.Text_align");
_Static_assert(CP0_APP_KEY_RELEASED == 0 && CP0_APP_KEY_PRESSED == 1 && CP0_APP_KEY_REPEATED == 2,
               "Lvgl.App.key_state");
_Static_assert(CP0_APP_MOD_SHIFT == 1 && CP0_APP_MOD_CTRL == 2 && CP0_APP_MOD_ALT == 4, "Lvgl.App.Mod");
