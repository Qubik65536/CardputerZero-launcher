// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! The C functions this app calls: LVGL 9.5 and cp0_app.h, the launcher's C API for
//! apps in other languages (ext_components/cp0_lvgl/include/cp0_app.h).
//!
//! Zig 0.17 has no @cImport, and `zig translate-c` on lvgl.h takes minutes, so this
//! file declares by hand exactly what the app uses, with the C names, so LVGL's
//! documentation (https://docs.lvgl.io/9.5/) applies as written. build.zig links the
//! runtime that defines them (scripts/lvgl-runtime).
//!
//! To call more of LVGL:
//!   1. Find the function in SDK/github_source/lvgl/lvgl_9_5/lvgl/src (for example
//!      `grep -rn "lv_arc_set_value" SDK/github_source/lvgl/lvgl_9_5/lvgl/src`).
//!   2. Copy its signature here as `pub extern fn`, translating the types:
//!        lv_obj_t *            *Obj (?*Obj where NULL is allowed), const: *const Obj
//!        const char *          [*:0]const u8
//!        int32_t / uint32_t    i32 / u32 (coordinates, sizes and values are int32_t)
//!        bool                  bool
//!        lv_color_t            Color (passed by value)
//!        lv_opa_t              u8
//!        lv_style_selector_t   u32 (part | state), lv_state_t and lv_part_t: u32
//!        lv_anim_enable_t      bool
//!        other C enums         an enum(c_int) below, or c_int
//!        void *                ?*anyopaque
//!   3. Constants: copy the value from the header (enums count up from the previous
//!      value). Macros and `static inline` functions have no symbol to link against:
//!      write them in Zig, like pct() and setPadAll() below.
//! All LVGL calls must happen on the LVGL thread: in the cp0_app callbacks, LVGL event
//! callbacks and timer callbacks, which is where this app makes them.

const std = @import("std");

// --- Types ---------------------------------------------------------------------------

/// Every widget is an lv_obj_t; LVGL owns the memory.
pub const Obj = opaque {};
pub const Font = opaque {};
pub const Event = opaque {};
pub const Timer = opaque {};
pub const Group = opaque {};
/// lv_indev_t: an input device (the keypad, the mouse in the simulator window).
pub const Indev = opaque {};
pub const Display = opaque {};
pub const Theme = opaque {};
/// lv_obj_class_t: a widget type, such as lv_dropdown_class (see lv_obj_check_type).
pub const ObjClass = opaque {};

/// lv_color_t: 24-bit color, blue first in memory.
pub const Color = extern struct {
    blue: u8,
    green: u8,
    red: u8,
};

pub const EventCb = *const fn (event: *Event) callconv(.c) void;
pub const TimerCb = *const fn (timer: *Timer) callconv(.c) void;

// --- Constants (values from the LVGL 9.5 headers) ------------------------------------

/// lv_align_t (misc/lv_area.h).
pub const Align = enum(c_int) {
    default = 0,
    top_left,
    top_mid,
    top_right,
    bottom_left,
    bottom_mid,
    bottom_right,
    left_mid,
    right_mid,
    center,
};

/// lv_event_code_t (misc/lv_event.h): the codes this app uses.
pub const EventCode = enum(c_int) {
    all = 0,
    short_clicked = 4,
    long_pressed_repeat = 9,
    clicked = 10,
    /// A key for the focused object; lv_event_get_key() tells which.
    key = 17,
    focused = 19,
    defocused = 20,
    value_changed = 35,
    /// A process has finished: ENTER in a one-line text area, for example.
    ready = 38,
    /// Sent before the object and then its children are deleted: free what refers to them.
    delete = 42,
    _,
};

/// `code` | LV_EVENT_PREPROCESS: the callback runs before the widget's own handling of
/// the event, and lv_event_stop_processing() can keep the widget from seeing it.
pub fn preprocess(code: EventCode) EventCode {
    return @fromBackingInt(@backingInt(code) | 0x8000);
}

/// lv_key_t (core/lv_group.h): the keys LVGL's keypad input device sends besides
/// characters. (Named lv_key so they are not mistaken for the Linux key codes of Key.code.)
pub const lv_key = struct {
    pub const up: u32 = 17;
    pub const down: u32 = 18;
    pub const right: u32 = 19;
    pub const left: u32 = 20;
};

/// lv_indev_type_t (indev/lv_indev.h).
pub const IndevType = enum(c_int) { none = 0, pointer, keypad, button, encoder };

/// lv_flex_flow_t (layouts/flex/lv_flex.h): the flows this app uses.
pub const FlexFlow = enum(c_int) {
    row = 0,
    column = 1,
    _,
};

/// lv_flex_align_t (layouts/flex/lv_flex.h).
pub const FlexAlign = enum(c_int) { start = 0, end, center, space_evenly, space_around, space_between };

/// lv_palette_t (misc/lv_palette.h): the palettes this app uses.
pub const Palette = enum(c_int) {
    blue = 5,
    _,
};

/// lv_state_t (core/lv_obj_style.h): the states this app uses. A style selector is
/// `part | state`; 0 is the main part in the default state.
pub const state = struct {
    pub const default: u32 = 0;
    pub const checked: u32 = 1 << 2;
};

/// lv_obj_flag_t (core/lv_obj.h).
pub const obj_flag = struct {
    pub const hidden: u32 = 1 << 0;
    pub const clickable: u32 = 1 << 1;
    pub const scrollable: u32 = 1 << 4;
    /// Scroll the object into view when it gets the focus.
    pub const scroll_on_focus: u32 = 1 << 10;
};

/// lv_opa_t values (misc/lv_color.h).
pub const opa_transp: u8 = 0;
pub const opa_cover: u8 = 255;

/// lv_anim_enable_t (misc/lv_anim.h).
pub const anim_off = false;
pub const anim_on = true;

/// lv_color_format_t (misc/lv_color.h): the canvas formats this app uses.
pub const ColorFormat = enum(c_int) {
    rgb565 = 0x12,
    _,
};

/// LV_SIZE_CONTENT (misc/lv_area.h): size a widget to fit its children or text.
pub const size_content: i32 = 0x3FFF_FFFF;

/// LV_PCT(x) (a macro): a size or position in percent of the parent.
pub fn pct(percent: i32) i32 {
    const special: i32 = 1 << 29; // LV_COORD_TYPE_SPEC
    const max: i32 = ((1 << 29) - 2) / 2; // LV_PCT_POS_MAX
    return special | if (percent < 0) max - @max(percent, -max) else @min(percent, max);
}

/// lv_color_hex() as a Zig function: 0xRRGGBB to a Color.
pub fn color(hex: u32) Color {
    return .{ .red = @truncate(hex >> 16), .green = @truncate(hex >> 8), .blue = @truncate(hex) };
}

// --- Objects (core/lv_obj.h, lv_obj_pos.h, lv_obj_style.h) -----------------------------
// The *_create functions never return NULL: this runtime is built with
// LV_USE_ASSERT_MALLOC, so LVGL stops in its assert handler when memory runs out.

pub extern fn lv_obj_create(parent: ?*Obj) *Obj;
pub extern fn lv_obj_remove_style_all(obj: *Obj) void;
pub extern fn lv_obj_set_pos(obj: *Obj, x: i32, y: i32) void;
pub extern fn lv_obj_set_size(obj: *Obj, width: i32, height: i32) void;
pub extern fn lv_obj_set_width(obj: *Obj, width: i32) void;
pub extern fn lv_obj_align(obj: *Obj, alignment: Align, x_offset: i32, y_offset: i32) void;
pub extern fn lv_obj_center(obj: *Obj) void;
pub extern fn lv_obj_add_flag(obj: *Obj, flags: u32) void;
pub extern fn lv_obj_remove_flag(obj: *Obj, flags: u32) void;
pub extern fn lv_obj_has_flag(obj: *const Obj, flags: u32) bool;
pub extern fn lv_obj_add_state(obj: *Obj, states: u32) void;
pub extern fn lv_obj_has_state(obj: *const Obj, states: u32) bool;
/// Redraw the object at the next refresh.
pub extern fn lv_obj_invalidate(obj: *const Obj) void;
/// Ask the object again how far it draws outside its area (shadows, outlines).
pub extern fn lv_obj_refresh_ext_draw_size(obj: *Obj) void;
pub extern fn lv_obj_check_type(obj: *const Obj, class: *const ObjClass) bool;
pub extern fn lv_obj_get_group(obj: *const Obj) ?*Group;

/// Show or hide an object (LV_OBJ_FLAG_HIDDEN).
pub fn setHidden(obj: *Obj, hidden: bool) void {
    if (hidden) lv_obj_add_flag(obj, obj_flag.hidden) else lv_obj_remove_flag(obj, obj_flag.hidden);
}

// --- Events (core/lv_obj_event.h, misc/lv_event.h) -------------------------------------

/// Returns the lv_event_dsc_t * for lv_obj_remove_event_dsc(); see onEvent().
pub extern fn lv_obj_add_event_cb(obj: *Obj, callback: EventCb, filter: EventCode, user_data: ?*anyopaque) ?*anyopaque;
pub extern fn lv_event_get_user_data(event: *Event) ?*anyopaque;
/// Without the LV_EVENT_PREPROCESS bit.
pub extern fn lv_event_get_code(event: *Event) EventCode;
/// The object the event was sent to (never NULL in an object's event callback).
pub extern fn lv_event_get_target_obj(event: *Event) *Obj;
/// For .key: an lv_key value or the character the key types.
pub extern fn lv_event_get_key(event: *Event) u32;
/// No further event callbacks run for this event, nor the widget's own handling.
pub extern fn lv_event_stop_processing(event: *Event) void;

/// Call `callback` with `user_data` when `obj` gets the event `code`.
pub fn onEvent(obj: *Obj, code: EventCode, callback: EventCb, user_data: ?*anyopaque) void {
    _ = lv_obj_add_event_cb(obj, callback, code, user_data);
}

/// The user_data given to onEvent(), as a pointer to `T`.
pub fn eventUserData(comptime T: type, event: *Event) *T {
    return @ptrCast(@alignCast(lv_event_get_user_data(event).?));
}

// --- Styles (core/lv_obj_style_gen.h): `selector` is part | state ------------------------

pub extern fn lv_obj_set_style_bg_color(obj: *Obj, value: Color, selector: u32) void;
pub extern fn lv_obj_set_style_bg_opa(obj: *Obj, value: u8, selector: u32) void;
pub extern fn lv_obj_set_style_border_width(obj: *Obj, value: i32, selector: u32) void;
pub extern fn lv_obj_set_style_pad_left(obj: *Obj, value: i32, selector: u32) void;
pub extern fn lv_obj_set_style_pad_right(obj: *Obj, value: i32, selector: u32) void;
pub extern fn lv_obj_set_style_pad_top(obj: *Obj, value: i32, selector: u32) void;
pub extern fn lv_obj_set_style_pad_bottom(obj: *Obj, value: i32, selector: u32) void;
pub extern fn lv_obj_set_style_text_color(obj: *Obj, value: Color, selector: u32) void;
pub extern fn lv_obj_set_style_text_font(obj: *Obj, value: *const Font, selector: u32) void;
/// The gap between the rows / columns of a flex layout.
pub extern fn lv_obj_set_style_pad_row(obj: *Obj, value: i32, selector: u32) void;
pub extern fn lv_obj_set_style_pad_column(obj: *Obj, value: i32, selector: u32) void;

// lv_obj_set_style_pad_hor/_ver/_all are static inline in C, so they are here in Zig.

pub fn setPadHor(obj: *Obj, value: i32, selector: u32) void {
    lv_obj_set_style_pad_left(obj, value, selector);
    lv_obj_set_style_pad_right(obj, value, selector);
}

pub fn setPadVer(obj: *Obj, value: i32, selector: u32) void {
    lv_obj_set_style_pad_top(obj, value, selector);
    lv_obj_set_style_pad_bottom(obj, value, selector);
}

pub fn setPadAll(obj: *Obj, value: i32, selector: u32) void {
    setPadHor(obj, value, selector);
    setPadVer(obj, value, selector);
}

// --- Flex layout (layouts/flex/lv_flex.h) ------------------------------------------------

/// Lay out the children in a row or a column (this also sets the flex layout).
pub extern fn lv_obj_set_flex_flow(obj: *Obj, flow: FlexFlow) void;
pub extern fn lv_obj_set_flex_align(obj: *Obj, main_place: FlexAlign, cross_place: FlexAlign, track_cross_place: FlexAlign) void;
/// A child's share of the free space along the flow.
pub extern fn lv_obj_set_flex_grow(obj: *Obj, grow: u8) void;

// --- Theme (themes/default/lv_theme_default.h, display/lv_display.h, misc/lv_palette.h) ----

pub extern fn lv_display_get_default() ?*Display;
/// Initialize (or update) the default theme; it styles every widget created afterwards.
pub extern fn lv_theme_default_init(display: ?*Display, primary: Color, secondary: Color, dark: bool, font: *const Font) *Theme;
/// Use `theme` for the display's widgets; the existing ones are restyled.
pub extern fn lv_display_set_theme(display: ?*Display, theme: *Theme) void;
pub extern fn lv_palette_main(palette: Palette) Color;

// --- Fonts (font/lv_font.h); the runtime enables Montserrat 12, 14 and 28 ----------------

pub extern const lv_font_montserrat_12: Font;
pub extern const lv_font_montserrat_14: Font;
pub extern const lv_font_montserrat_28: Font;
/// How wide `letter` is drawn when `next` follows it (kerning), in pixels.
pub extern fn lv_font_get_glyph_width(font: *const Font, letter: u32, next: u32) u16;

// --- Widgets -----------------------------------------------------------------------------

// Label (widgets/label/lv_label.h). The label keeps its own copy of the text.
pub extern fn lv_label_create(parent: ?*Obj) *Obj;
pub extern fn lv_label_set_text(obj: *Obj, text: [*:0]const u8) void;

/// lv_label_set_text() for a Zig slice (at most 255 bytes are shown).
pub fn setText(label: *Obj, text: []const u8) void {
    var buffer: [256]u8 = undefined;
    const length = @min(text.len, buffer.len - 1);
    @memcpy(buffer[0..length], text[0..length]);
    buffer[length] = 0;
    lv_label_set_text(label, buffer[0..length :0]);
}

// Image (widgets/image/lv_image.h). `source` is a file path (see filePath) or an image descriptor.
pub extern fn lv_image_create(parent: ?*Obj) *Obj;
pub extern fn lv_image_set_src(obj: *Obj, source: *const anyopaque) void;

// Canvas (widgets/canvas/lv_canvas.h): shows a pixel buffer the app owns.
pub extern fn lv_canvas_create(parent: ?*Obj) *Obj;
pub extern fn lv_canvas_set_buffer(obj: *Obj, buffer: *anyopaque, width: i32, height: i32, format: ColorFormat) void;

// Button (widgets/button/lv_button.h): a clickable container; put a label inside.
pub extern fn lv_button_create(parent: ?*Obj) *Obj;

// Text area (widgets/textarea/lv_textarea.h).
pub extern fn lv_textarea_create(parent: ?*Obj) *Obj;
pub extern fn lv_textarea_set_one_line(obj: *Obj, enabled: bool) void;
pub extern fn lv_textarea_set_placeholder_text(obj: *Obj, text: [*:0]const u8) void;
pub extern fn lv_textarea_set_max_length(obj: *Obj, length: u32) void;
pub extern fn lv_textarea_get_text(obj: *const Obj) [*:0]const u8;

// Slider (widgets/slider/lv_slider.h).
pub extern fn lv_slider_create(parent: ?*Obj) *Obj;
pub extern fn lv_slider_set_range(obj: *Obj, min: i32, max: i32) void;
pub extern fn lv_slider_set_value(obj: *Obj, value: i32, anim: bool) void;
pub extern fn lv_slider_get_value(obj: *const Obj) i32;

// Switch (widgets/switch/lv_switch.h): on while it has state.checked.
pub extern fn lv_switch_create(parent: ?*Obj) *Obj;

// Checkbox (widgets/checkbox/lv_checkbox.h): checked while it has state.checked.
pub extern fn lv_checkbox_create(parent: ?*Obj) *Obj;
pub extern fn lv_checkbox_set_text(obj: *Obj, text: [*:0]const u8) void;

// Spinbox (widgets/spinbox/lv_spinbox.h): a number in a text area.
pub extern fn lv_spinbox_create(parent: ?*Obj) *Obj;
pub extern fn lv_spinbox_set_range(obj: *Obj, min: i32, max: i32) void;
/// `digit_count` digits, a decimal point after `separator_position` of them (0: none).
pub extern fn lv_spinbox_set_digit_format(obj: *Obj, digit_count: u32, separator_position: u32) void;
pub extern fn lv_spinbox_set_value(obj: *Obj, value: i32) void;
pub extern fn lv_spinbox_get_value(obj: *Obj) i32;
pub extern fn lv_spinbox_increment(obj: *Obj) void;
pub extern fn lv_spinbox_decrement(obj: *Obj) void;

// Dropdown (widgets/dropdown/lv_dropdown.h): options separated by "\n".
pub extern const lv_dropdown_class: ObjClass;
pub extern fn lv_dropdown_create(parent: ?*Obj) *Obj;
pub extern fn lv_dropdown_set_options(obj: *Obj, options: [*:0]const u8) void;
pub extern fn lv_dropdown_set_selected(obj: *Obj, option: u32) void;
pub extern fn lv_dropdown_get_selected(obj: *const Obj) u32;
pub extern fn lv_dropdown_is_open(obj: *Obj) bool;
pub extern fn lv_dropdown_close(obj: *Obj) void;

// --- Focus groups (core/lv_group.h) ------------------------------------------------------

pub extern fn lv_group_create() *Group;
pub extern fn lv_group_delete(group: *Group) void;
pub extern fn lv_group_add_obj(group: *Group, obj: *Obj) void;
pub extern fn lv_group_remove_obj(obj: *Obj) void;
pub extern fn lv_group_focus_obj(obj: *Obj) void;
pub extern fn lv_group_focus_next(group: *Group) void;
pub extern fn lv_group_focus_prev(group: *Group) void;
pub extern fn lv_group_get_focused(group: *const Group) ?*Obj;
pub extern fn lv_group_set_wrap(group: *Group, enabled: bool) void;

// --- Input devices (indev/lv_indev.h) ---------------------------------------------------

/// The input device after `indev` (the first one for null); null after the last.
pub extern fn lv_indev_get_next(indev: ?*Indev) ?*Indev;
/// The input device whose event is being handled, if any.
pub extern fn lv_indev_active() ?*Indev;
pub extern fn lv_indev_get_type(indev: *const Indev) IndevType;
/// The focus group a keypad sends its keys to.
pub extern fn lv_indev_get_group(indev: *const Indev) ?*Group;
pub extern fn lv_indev_set_group(indev: *Indev, group: ?*Group) void;
/// Ignore the key or press that is down now until it is released.
pub extern fn lv_indev_wait_release(indev: *Indev) void;

// --- Timers (misc/lv_timer.h) ------------------------------------------------------------

/// Run `callback` every `period_ms` milliseconds.
pub extern fn lv_timer_create(callback: TimerCb, period_ms: u32, user_data: ?*anyopaque) *Timer;
pub extern fn lv_timer_delete(timer: *Timer) void;
pub extern fn lv_timer_pause(timer: *Timer) void;
pub extern fn lv_timer_resume(timer: *Timer) void;
pub extern fn lv_timer_get_user_data(timer: *Timer) ?*anyopaque;

/// The user_data given to lv_timer_create(), as a pointer to `T`.
pub fn timerUserData(comptime T: type, timer: *Timer) *T {
    return @ptrCast(@alignCast(lv_timer_get_user_data(timer).?));
}

// --- cp0_app.h: the page, keys and resources ----------------------------------------------

/// cp0_app_key_t: one key event. `text` is valid only during the callback.
pub const Key = extern struct {
    /// Linux key code (KEY_ESC = 1, KEY_ENTER = 28, KEY_F = 33, ...).
    code: u32,
    /// CP0_APP_KEY_RELEASED / _PRESSED / _REPEATED.
    state: c_int,
    /// CP0_APP_MOD_* bits.
    mods: u32,
    /// UTF-8 text the key types, with Shift and the symbol layer applied; "" if none.
    text: [*:0]const u8,

    pub const released = 0;
    pub const pressed = 1;
    pub const repeated = 2;

    pub const mod_shift: u32 = 1 << 0;
    pub const mod_ctrl: u32 = 1 << 1;
    pub const mod_alt: u32 = 1 << 2;

    pub fn typed(key: *const Key) []const u8 {
        return std.mem.span(key.text);
    }
};

pub const SetupFn = *const fn (content: *Obj, user_data: ?*anyopaque) callconv(.c) void;
pub const KeyFn = *const fn (key: *const Key, user_data: ?*anyopaque) callconv(.c) void;

/// Set up LVGL, the display, the keyboard and the standard page (20 px top bar with
/// `title`, clock and battery above a 320x150 content area), call `setup` with the
/// content area, then run until cp0_app_quit(). Returns the process exit status.
pub extern fn cp0_app_run(title: [*:0]const u8, setup: SetupFn, on_key: ?KeyFn, user_data: ?*anyopaque) c_int;
pub extern fn cp0_app_quit() void;
pub extern fn cp0_app_set_title(title: [*:0]const u8) void;
pub extern fn cp0_app_content() ?*Obj;
pub extern fn cp0_app_screen() ?*Obj;
/// Nonzero: keys type text (F/X/Z/C are letters). Zero (the default): F/X/Z/C also
/// act as up/down/left/right, like in the launcher.
pub extern fn cp0_app_set_text_input(enabled: c_int) void;
/// Nonzero: keys reach only the key callback, not LVGL's focused widget.
pub extern fn cp0_app_set_keypad_intercept(enabled: c_int) void;
/// Writes the path of an installed resource file (APPLaunch/share/images/<name>, ...)
/// into `out`; returns the full length.
pub extern fn cp0_app_file_path(name: [*:0]const u8, out: [*]u8, size: usize) usize;

/// cp0_app_file_path() into `buffer`; null if the path does not fit.
pub fn filePath(buffer: []u8, name: [*:0]const u8) ?[:0]const u8 {
    const length = cp0_app_file_path(name, buffer.ptr, buffer.len);
    if (length >= buffer.len) return null;
    return buffer[0..length :0];
}

test "the macros written in Zig match LVGL's" {
    try std.testing.expectEqual(0x2000_0032, pct(50)); // LV_PCT(50)
    try std.testing.expectEqual(0x2000_0000 | (268435455 + 10), pct(-10)); // LV_PCT(-10)
    try std.testing.expectEqual(Color{ .blue = 0x5C, .green = 0x91, .red = 0xEC }, color(0xEC915C));
    try std.testing.expectEqual(0x8011, @backingInt(preprocess(.key))); // LV_EVENT_KEY | LV_EVENT_PREPROCESS
}
