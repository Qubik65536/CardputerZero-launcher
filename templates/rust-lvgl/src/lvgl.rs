// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! LVGL 9.5 and the cp0_app C API, declared by hand: exactly the functions,
//! fonts and constants this app uses, plus a thin layer that keeps `unsafe` in
//! this file so the screens read like the C++ template.
//!
//! The file has three parts:
//!
//! 1. `ffi`: the raw `extern "C"` declarations, copied from the C headers.
//! 2. Constants (`LV_STATE_FOCUSED`, `LV_PART_KNOB`, ...) under their C names,
//!    so LVGL's documentation and examples translate one to one.
//! 3. The safe-ish layer: `Obj` (any `lv_obj_t *`) with the common functions
//!    and style setters as methods, one type per widget (`Label`, `Slider`, ...)
//!    that derefs to `Obj`, `Font`, `Timer`, `Group`, `Indev`, `Event`, the
//!    default theme, callbacks that carry your data, and `run`/`quit`/... for
//!    cp0_app.
//!
//! How to call more of LVGL
//! ------------------------
//! 1. Find the function in the LVGL sources the runtime is built from:
//!    `grep -rn "lv_arc_set_value" SDK/github_source/lvgl/lvgl_9_5/lvgl/src`
//!    (from the repository root; `scripts/lvgl-runtime/build.sh desktop` downloads them).
//! 2. Copy its signature into the `extern "C"` block in `ffi`, translating the types:
//!
//!    ```text
//!    lv_obj_t *              *mut lv_obj_t (*const for const lv_obj_t *)
//!    const char *            *const c_char (pass a CString, see c_string)
//!    int32_t / uint32_t      i32 / u32 (coordinates are int32_t)
//!    bool                    bool; lv_anim_enable_t is a bool too
//!    lv_opa_t                u8
//!    lv_color_t              lv_color_t (3 bytes, passed by value)
//!    lv_style_selector_t     u32 (LV_PART_* | LV_STATE_*)
//!    C enums (lv_align_t, lv_state_t, lv_part_t, lv_obj_flag_t, ...) are
//!    int-sized: declare them as u32 / c_int and copy the values you need
//!    ```
//!
//!    Then add a method below that converts the arguments, like the existing ones.
//! 3. `static inline` functions and macros (`lv_obj_set_style_pad_all`, `LV_PCT`,
//!    `LV_SIZE_CONTENT`, ...) are not in the library: reimplement them in Rust
//!    (see `Obj::set_style_pad_all`; `LV_PCT(x)` is `x | 1 << 29` for x >= 0).
//! 4. Enum values: count them in the header (C enums start at 0), or compile a
//!    C file that prints them with the flags in `scripts/lvgl-runtime/out/desktop/cflags.txt`.
//! 5. Widgets must be enabled in the runtime's LVGL configuration
//!    (`scripts/lvgl-runtime/out/desktop/build/build/config/lvgl_config.h`); the
//!    linker reports a missing symbol otherwise.
//!
//! Threading: LVGL is single-threaded. Call everything from the setup or key
//! callback, LVGL event callbacks or timers, never from another thread.

#![allow(non_camel_case_types)] // C type names, kept so the declarations match the headers

use std::cell::Cell;
use std::ffi::{c_char, c_int, c_void, CStr, CString};
use std::ops::Deref;
use std::ptr::{self, NonNull};

// ---------------------------------------------------------------------------
// 1. Raw C declarations
// ---------------------------------------------------------------------------

/// Types and functions exactly as in the C headers (`lvgl/src/...` and
/// `ext_components/cp0_lvgl/include/cp0_app.h`).
pub mod ffi {
    use std::ffi::{c_char, c_int, c_void};

    /// Opaque C structs: only ever used behind pointers.
    #[repr(C)]
    pub struct lv_obj_t {
        _opaque: [u8; 0],
    }
    #[repr(C)]
    pub struct lv_event_t {
        _opaque: [u8; 0],
    }
    #[repr(C)]
    pub struct lv_timer_t {
        _opaque: [u8; 0],
    }
    #[repr(C)]
    pub struct lv_group_t {
        _opaque: [u8; 0],
    }
    #[repr(C)]
    pub struct lv_font_t {
        _opaque: [u8; 0],
    }
    #[repr(C)]
    pub struct lv_indev_t {
        _opaque: [u8; 0],
    }
    #[repr(C)]
    pub struct lv_display_t {
        _opaque: [u8; 0],
    }
    #[repr(C)]
    pub struct lv_theme_t {
        _opaque: [u8; 0],
    }
    #[repr(C)]
    pub struct lv_obj_class_t {
        _opaque: [u8; 0],
    }

    /// misc/lv_color.h: 24-bit color, blue first.
    #[repr(C)]
    #[derive(Clone, Copy, Debug, PartialEq, Eq)]
    pub struct lv_color_t {
        pub blue: u8,
        pub green: u8,
        pub red: u8,
    }

    pub type lv_opa_t = u8;
    pub type lv_style_selector_t = u32;
    pub type lv_state_t = u32; // C enum
    pub type lv_obj_flag_t = u32; // C enum
    pub type lv_align_t = c_int; // C enum
    pub type lv_event_code_t = c_int; // C enum
    pub type lv_color_format_t = c_int; // C enum
    pub type lv_flex_flow_t = c_int; // C enum
    pub type lv_flex_align_t = c_int; // C enum
    pub type lv_indev_type_t = c_int; // C enum
    pub type lv_palette_t = c_int; // C enum
    pub type lv_anim_enable_t = bool;
    pub type lv_result_t = c_int; // C enum

    pub type lv_event_cb_t = extern "C" fn(event: *mut lv_event_t);
    pub type lv_timer_cb_t = extern "C" fn(timer: *mut lv_timer_t);

    /// cp0_app.h: one key event.
    #[repr(C)]
    pub struct cp0_app_key_t {
        pub code: u32,
        pub state: c_int,
        pub mods: u32,
        pub text: *const c_char,
    }
    pub type cp0_app_setup_fn = extern "C" fn(content: *mut lv_obj_t, user_data: *mut c_void);
    pub type cp0_app_key_fn = extern "C" fn(key: *const cp0_app_key_t, user_data: *mut c_void);

    extern "C" {
        // cp0_app.h
        pub fn cp0_app_run(
            title: *const c_char,
            setup: cp0_app_setup_fn,
            on_key: Option<cp0_app_key_fn>,
            user_data: *mut c_void,
        ) -> c_int;
        pub fn cp0_app_quit();
        pub fn cp0_app_set_title(title: *const c_char);
        pub fn cp0_app_set_text_input(enabled: c_int);
        pub fn cp0_app_file_path(name: *const c_char, out: *mut c_char, size: usize) -> usize;

        // core/lv_obj.h, core/lv_obj_pos.h, core/lv_obj_style.h
        pub fn lv_obj_create(parent: *mut lv_obj_t) -> *mut lv_obj_t;
        pub fn lv_obj_add_flag(obj: *mut lv_obj_t, flag: lv_obj_flag_t);
        pub fn lv_obj_remove_flag(obj: *mut lv_obj_t, flag: lv_obj_flag_t);
        pub fn lv_obj_has_flag(obj: *const lv_obj_t, flag: lv_obj_flag_t) -> bool;
        pub fn lv_obj_add_state(obj: *mut lv_obj_t, state: lv_state_t);
        pub fn lv_obj_has_state(obj: *const lv_obj_t, state: lv_state_t) -> bool;
        pub fn lv_obj_check_type(obj: *const lv_obj_t, class_p: *const lv_obj_class_t) -> bool;
        pub fn lv_obj_set_pos(obj: *mut lv_obj_t, x: i32, y: i32);
        pub fn lv_obj_set_size(obj: *mut lv_obj_t, width: i32, height: i32);
        pub fn lv_obj_set_width(obj: *mut lv_obj_t, width: i32);
        pub fn lv_obj_align(obj: *mut lv_obj_t, align: lv_align_t, x_offset: i32, y_offset: i32);
        pub fn lv_obj_center(obj: *mut lv_obj_t);
        pub fn lv_obj_invalidate(obj: *const lv_obj_t) -> lv_result_t;
        pub fn lv_obj_remove_style_all(obj: *mut lv_obj_t);
        pub fn lv_obj_refresh_ext_draw_size(obj: *mut lv_obj_t);

        // layouts/flex/lv_flex.h
        pub fn lv_obj_set_flex_flow(obj: *mut lv_obj_t, flow: lv_flex_flow_t);
        pub fn lv_obj_set_flex_align(
            obj: *mut lv_obj_t,
            main_place: lv_flex_align_t,
            cross_place: lv_flex_align_t,
            track_cross_place: lv_flex_align_t,
        );
        pub fn lv_obj_set_flex_grow(obj: *mut lv_obj_t, grow: u8);

        // core/lv_obj_style_gen.h
        pub fn lv_obj_set_style_bg_color(obj: *mut lv_obj_t, value: lv_color_t, selector: lv_style_selector_t);
        pub fn lv_obj_set_style_bg_opa(obj: *mut lv_obj_t, value: lv_opa_t, selector: lv_style_selector_t);
        pub fn lv_obj_set_style_border_width(obj: *mut lv_obj_t, value: i32, selector: lv_style_selector_t);
        pub fn lv_obj_set_style_pad_top(obj: *mut lv_obj_t, value: i32, selector: lv_style_selector_t);
        pub fn lv_obj_set_style_pad_bottom(obj: *mut lv_obj_t, value: i32, selector: lv_style_selector_t);
        pub fn lv_obj_set_style_pad_left(obj: *mut lv_obj_t, value: i32, selector: lv_style_selector_t);
        pub fn lv_obj_set_style_pad_right(obj: *mut lv_obj_t, value: i32, selector: lv_style_selector_t);
        pub fn lv_obj_set_style_pad_row(obj: *mut lv_obj_t, value: i32, selector: lv_style_selector_t);
        pub fn lv_obj_set_style_pad_column(obj: *mut lv_obj_t, value: i32, selector: lv_style_selector_t);
        pub fn lv_obj_set_style_text_color(obj: *mut lv_obj_t, value: lv_color_t, selector: lv_style_selector_t);
        pub fn lv_obj_set_style_text_font(obj: *mut lv_obj_t, value: *const lv_font_t, selector: lv_style_selector_t);

        // core/lv_obj_event.h, misc/lv_event.h
        pub fn lv_obj_add_event_cb(
            obj: *mut lv_obj_t,
            event_cb: lv_event_cb_t,
            filter: lv_event_code_t,
            user_data: *mut c_void,
        ) -> *mut c_void;
        pub fn lv_event_get_user_data(event: *mut lv_event_t) -> *mut c_void;
        pub fn lv_event_get_code(event: *mut lv_event_t) -> lv_event_code_t;
        pub fn lv_event_get_target_obj(event: *mut lv_event_t) -> *mut lv_obj_t;
        pub fn lv_event_get_key(event: *mut lv_event_t) -> u32;
        pub fn lv_event_stop_processing(event: *mut lv_event_t);

        // core/lv_group.h
        pub fn lv_group_create() -> *mut lv_group_t;
        pub fn lv_group_delete(group: *mut lv_group_t);
        pub fn lv_group_add_obj(group: *mut lv_group_t, obj: *mut lv_obj_t);
        pub fn lv_group_remove_obj(obj: *mut lv_obj_t);
        pub fn lv_obj_get_group(obj: *const lv_obj_t) -> *mut lv_group_t;
        pub fn lv_group_focus_obj(obj: *mut lv_obj_t);
        pub fn lv_group_focus_next(group: *mut lv_group_t);
        pub fn lv_group_focus_prev(group: *mut lv_group_t);
        pub fn lv_group_get_focused(group: *const lv_group_t) -> *mut lv_obj_t;
        pub fn lv_group_set_wrap(group: *mut lv_group_t, enabled: bool);

        // indev/lv_indev.h
        pub fn lv_indev_get_next(indev: *mut lv_indev_t) -> *mut lv_indev_t;
        pub fn lv_indev_active() -> *mut lv_indev_t;
        pub fn lv_indev_get_type(indev: *const lv_indev_t) -> lv_indev_type_t;
        pub fn lv_indev_get_group(indev: *const lv_indev_t) -> *mut lv_group_t;
        pub fn lv_indev_set_group(indev: *mut lv_indev_t, group: *mut lv_group_t);
        pub fn lv_indev_wait_release(indev: *mut lv_indev_t);

        // display/lv_display.h, themes/default/lv_theme_default.h, misc/lv_palette.h
        pub fn lv_display_get_default() -> *mut lv_display_t;
        pub fn lv_display_set_theme(disp: *mut lv_display_t, theme: *mut lv_theme_t);
        pub fn lv_theme_default_init(
            disp: *mut lv_display_t,
            color_primary: lv_color_t,
            color_secondary: lv_color_t,
            dark: bool,
            font: *const lv_font_t,
        ) -> *mut lv_theme_t;
        pub fn lv_palette_main(palette: lv_palette_t) -> lv_color_t;

        // misc/lv_timer.h
        pub fn lv_timer_create(timer_cb: lv_timer_cb_t, period: u32, user_data: *mut c_void) -> *mut lv_timer_t;
        pub fn lv_timer_pause(timer: *mut lv_timer_t);
        pub fn lv_timer_resume(timer: *mut lv_timer_t);
        pub fn lv_timer_get_user_data(timer: *mut lv_timer_t) -> *mut c_void;

        // font/lv_font.h; the fonts are enabled in the runtime's lvgl_config.h
        pub fn lv_font_get_glyph_width(font: *const lv_font_t, letter: u32, letter_next: u32) -> u16;
        pub static lv_font_montserrat_12: lv_font_t;
        pub static lv_font_montserrat_14: lv_font_t;
        pub static lv_font_montserrat_28: lv_font_t;

        // widgets/*/lv_*.h
        pub fn lv_label_create(parent: *mut lv_obj_t) -> *mut lv_obj_t;
        pub fn lv_label_set_text(obj: *mut lv_obj_t, text: *const c_char);
        pub fn lv_image_create(parent: *mut lv_obj_t) -> *mut lv_obj_t;
        pub fn lv_image_set_src(obj: *mut lv_obj_t, src: *const c_void);
        pub fn lv_canvas_create(parent: *mut lv_obj_t) -> *mut lv_obj_t;
        pub fn lv_canvas_set_buffer(obj: *mut lv_obj_t, buf: *mut c_void, w: i32, h: i32, cf: lv_color_format_t);
        pub fn lv_button_create(parent: *mut lv_obj_t) -> *mut lv_obj_t;
        pub fn lv_textarea_create(parent: *mut lv_obj_t) -> *mut lv_obj_t;
        pub fn lv_textarea_set_one_line(obj: *mut lv_obj_t, enabled: bool);
        pub fn lv_textarea_set_placeholder_text(obj: *mut lv_obj_t, text: *const c_char);
        pub fn lv_textarea_set_max_length(obj: *mut lv_obj_t, num: u32);
        pub fn lv_textarea_get_text(obj: *const lv_obj_t) -> *const c_char;
        pub fn lv_slider_create(parent: *mut lv_obj_t) -> *mut lv_obj_t;
        pub fn lv_slider_set_range(obj: *mut lv_obj_t, min: i32, max: i32);
        pub fn lv_slider_set_value(obj: *mut lv_obj_t, value: i32, anim: lv_anim_enable_t);
        pub fn lv_slider_get_value(obj: *const lv_obj_t) -> i32;
        pub fn lv_spinbox_create(parent: *mut lv_obj_t) -> *mut lv_obj_t;
        pub fn lv_spinbox_set_range(obj: *mut lv_obj_t, min_value: i32, max_value: i32);
        pub fn lv_spinbox_set_digit_format(obj: *mut lv_obj_t, digit_count: u32, sep_pos: u32);
        pub fn lv_spinbox_set_value(obj: *mut lv_obj_t, value: i32);
        pub fn lv_spinbox_get_value(obj: *mut lv_obj_t) -> i32;
        pub fn lv_spinbox_increment(obj: *mut lv_obj_t);
        pub fn lv_spinbox_decrement(obj: *mut lv_obj_t);
        pub fn lv_dropdown_create(parent: *mut lv_obj_t) -> *mut lv_obj_t;
        pub fn lv_dropdown_set_options(obj: *mut lv_obj_t, options: *const c_char);
        pub fn lv_dropdown_set_selected(obj: *mut lv_obj_t, sel_opt: u32);
        pub fn lv_dropdown_get_selected(obj: *const lv_obj_t) -> u32;
        pub fn lv_dropdown_get_selected_str(obj: *const lv_obj_t, buf: *mut c_char, buf_size: u32);
        pub fn lv_dropdown_is_open(obj: *mut lv_obj_t) -> bool;
        pub fn lv_dropdown_close(obj: *mut lv_obj_t);
        pub static lv_dropdown_class: lv_obj_class_t;
        pub fn lv_switch_create(parent: *mut lv_obj_t) -> *mut lv_obj_t;
        pub fn lv_checkbox_create(parent: *mut lv_obj_t) -> *mut lv_obj_t;
        pub fn lv_checkbox_set_text(obj: *mut lv_obj_t, text: *const c_char);
    }
}

use ffi::*;

// ---------------------------------------------------------------------------
// 2. Constants, as in the C headers (checked against LVGL 9.5)
// ---------------------------------------------------------------------------

// lv_obj_flag_t (core/lv_obj.h)
pub const LV_OBJ_FLAG_HIDDEN: lv_obj_flag_t = 1 << 0;
pub const LV_OBJ_FLAG_CLICKABLE: lv_obj_flag_t = 1 << 1;
pub const LV_OBJ_FLAG_SCROLLABLE: lv_obj_flag_t = 1 << 4;
pub const LV_OBJ_FLAG_SCROLL_ON_FOCUS: lv_obj_flag_t = 1 << 10; // scroll the object into view when focused

// lv_state_t (core/lv_obj_style.h); also usable as style selectors
pub const LV_STATE_CHECKED: lv_state_t = 1 << 2;

// lv_opa_t (misc/lv_color.h)
pub const LV_OPA_TRANSP: lv_opa_t = 0;
pub const LV_OPA_COVER: lv_opa_t = 255;

// lv_align_t (misc/lv_area.h)
pub const LV_ALIGN_TOP_MID: lv_align_t = 2;
pub const LV_ALIGN_TOP_RIGHT: lv_align_t = 3;

// Sizes (misc/lv_area.h): LV_SIZE_CONTENT and LV_PCT are macros in C.
/// Width or height that fits the children (`LV_SIZE_CONTENT`).
pub const LV_SIZE_CONTENT: i32 = (1 << 29) | ((1 << 29) - 1);

/// `percent` % of the parent's size (`LV_PCT`), for `set_size`/`set_width`.
pub const fn lv_pct(percent: i32) -> i32 {
    const MAX: i32 = ((1 << 29) - 2) / 2; // LV_PCT_POS_MAX
    let stored = if percent < 0 {
        MAX - if percent > -MAX { percent } else { -MAX }
    } else if percent < MAX {
        percent
    } else {
        MAX
    };
    stored | 1 << 29
}

// lv_event_code_t (misc/lv_event.h)
pub const LV_EVENT_ALL: lv_event_code_t = 0;
pub const LV_EVENT_SHORT_CLICKED: lv_event_code_t = 4;
pub const LV_EVENT_LONG_PRESSED_REPEAT: lv_event_code_t = 9; // repeatedly while held down
pub const LV_EVENT_CLICKED: lv_event_code_t = 10;
pub const LV_EVENT_KEY: lv_event_code_t = 17;
pub const LV_EVENT_FOCUSED: lv_event_code_t = 19;
pub const LV_EVENT_DEFOCUSED: lv_event_code_t = 20;
pub const LV_EVENT_VALUE_CHANGED: lv_event_code_t = 35;
pub const LV_EVENT_READY: lv_event_code_t = 38; // e.g. ENTER in a one-line text area
pub const LV_EVENT_DELETE: lv_event_code_t = 42; // sent before the object's children are deleted
/// Flag: `LV_EVENT_KEY | LV_EVENT_PREPROCESS` runs the handler before the
/// widget's own one, which `Event::stop_processing` can then skip.
pub const LV_EVENT_PREPROCESS: lv_event_code_t = 0x8000;

// lv_key_t (core/lv_group.h): `Event::key` for navigation keys; typing keys
// give their character.
pub const LV_KEY_UP: u32 = 17;
pub const LV_KEY_DOWN: u32 = 18;
pub const LV_KEY_RIGHT: u32 = 19;
pub const LV_KEY_LEFT: u32 = 20;

// lv_anim_enable_t (misc/lv_anim.h)
pub const LV_ANIM_OFF: lv_anim_enable_t = false;

// lv_color_format_t (misc/lv_color.h)
const LV_COLOR_FORMAT_RGB565: lv_color_format_t = 0x12;

// lv_flex_flow_t, lv_flex_align_t (layouts/flex/lv_flex.h)
pub const LV_FLEX_FLOW_ROW: lv_flex_flow_t = 0;
pub const LV_FLEX_FLOW_COLUMN: lv_flex_flow_t = 1;
pub const LV_FLEX_ALIGN_START: lv_flex_align_t = 0;
pub const LV_FLEX_ALIGN_CENTER: lv_flex_align_t = 2;

// lv_indev_type_t (indev/lv_indev.h)
pub const LV_INDEV_TYPE_KEYPAD: lv_indev_type_t = 2;

// lv_palette_t (misc/lv_palette.h)
pub const LV_PALETTE_BLUE: lv_palette_t = 5;

/// Linux key codes (linux/input-event-codes.h), as cp0_app reports them.
pub mod keys {
    pub const ESC: u32 = 1;
    pub const DIGIT_1: u32 = 2;
    pub const DIGIT_2: u32 = 3;
    pub const DIGIT_3: u32 = 4;
    pub const DIGIT_4: u32 = 5;
    pub const BACKSPACE: u32 = 14;
    pub const TAB: u32 = 15;
    pub const ENTER: u32 = 28;
    pub const F: u32 = 33;
    pub const Z: u32 = 44;
    pub const X: u32 = 45;
    pub const C: u32 = 46;
    pub const SPACE: u32 = 57;
    pub const UP: u32 = 103;
    pub const LEFT: u32 = 105;
    pub const RIGHT: u32 = 106;
    pub const DOWN: u32 = 108;
}

// ---------------------------------------------------------------------------
// 3. The safe-ish layer
// ---------------------------------------------------------------------------

/// `&str` to a C string. LVGL copies the strings it keeps (label text,
/// placeholders, dropdown options, image paths), so a temporary is enough.
/// A NUL inside the text ends it early.
fn c_string(text: &str) -> CString {
    let end = text.find('\0').unwrap_or(text.len());
    CString::new(&text[..end]).expect("NUL bytes were cut off")
}

/// 0xRRGGBB to an LVGL color (`lv_color_hex`, done in Rust so it can be a const).
pub const fn color_hex(hex: u32) -> lv_color_t {
    lv_color_t { blue: (hex & 0xFF) as u8, green: ((hex >> 8) & 0xFF) as u8, red: ((hex >> 16) & 0xFF) as u8 }
}

/// The main shade of one of LVGL's palette colors (`LV_PALETTE_BLUE`, ...).
pub fn palette_main(palette: lv_palette_t) -> lv_color_t {
    unsafe { lv_palette_main(palette) }
}

/// A font compiled into the runtime.
#[derive(Clone, Copy)]
pub struct Font(&'static lv_font_t);

impl Font {
    pub fn montserrat_12() -> Font {
        Font(unsafe { &lv_font_montserrat_12 })
    }

    pub fn montserrat_14() -> Font {
        Font(unsafe { &lv_font_montserrat_14 })
    }

    pub fn montserrat_28() -> Font {
        Font(unsafe { &lv_font_montserrat_28 })
    }

    /// Width in pixels of `letter` when `next` follows it (kerning); `next` 0 = nothing.
    pub fn glyph_width(self, letter: char, next: char) -> i32 {
        i32::from(unsafe { lv_font_get_glyph_width(self.0, letter as u32, next as u32) })
    }
}

/// Make LVGL's default theme the theme of the display (`lv_theme_default_init`
/// and `lv_display_set_theme`): `primary` is the accent color, `secondary` the
/// second one, `dark` picks dark mode, `font` the default text font. Objects
/// created afterwards take their look from it; calling it again restyles the
/// existing ones.
pub fn set_default_theme(primary: lv_color_t, secondary: lv_color_t, dark: bool, font: Font) {
    unsafe {
        let display = lv_display_get_default();
        let theme = lv_theme_default_init(display, primary, secondary, dark, font.0);
        lv_display_set_theme(display, theme);
    }
}

/// A function and the data it runs with, behind one C `user_data` pointer.
/// Callbacks live as long as the app, like the screens they belong to.
struct Callback<T: 'static> {
    data: &'static T,
    function: fn(&'static T),
}

impl<T: 'static> Callback<T> {
    fn leak(data: &'static T, function: fn(&'static T)) -> *mut c_void {
        Box::leak(Box::new(Callback { data, function })) as *mut Callback<T> as *mut c_void
    }

    /// Safety: `user_data` must come from `Callback::<T>::leak`.
    unsafe fn call(user_data: *mut c_void) {
        let callback = &*(user_data as *const Callback<T>);
        (callback.function)(callback.data);
    }
}

extern "C" fn event_trampoline<T: 'static>(event: *mut lv_event_t) {
    unsafe { Callback::<T>::call(lv_event_get_user_data(event)) }
}

extern "C" fn timer_trampoline<T: 'static>(timer: *mut lv_timer_t) {
    unsafe { Callback::<T>::call(lv_timer_get_user_data(timer)) }
}

/// The event an `Obj::on_event_with` handler is running for. Only valid
/// during the call, so handlers get it by reference.
pub struct Event(NonNull<lv_event_t>);

/// A handler that also gets the event, with data of any `Copy` type (a widget,
/// a group, a `&'static` screen, ...).
struct EventHandler<D: Copy + 'static> {
    data: D,
    function: fn(D, &Event),
}

extern "C" fn event_handler_trampoline<D: Copy + 'static>(event: *mut lv_event_t) {
    let Some(event) = NonNull::new(event) else {
        return;
    };
    let handler = unsafe { &*(lv_event_get_user_data(event.as_ptr()) as *const EventHandler<D>) };
    (handler.function)(handler.data, &Event(event));
}

/// Any LVGL object (`lv_obj_t *`): the functions every widget has. LVGL owns
/// the object; `Obj` is a copyable handle, like the pointer in C.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Obj(NonNull<lv_obj_t>);

impl Obj {
    /// Wrap a pointer from C, e.g. the content area cp0_app passes to setup.
    fn from_ptr(ptr: *mut lv_obj_t) -> Obj {
        Obj(NonNull::new(ptr).expect("LVGL returned no object (out of memory?)"))
    }

    pub fn as_ptr(self) -> *mut lv_obj_t {
        self.0.as_ptr()
    }

    /// A plain object (`lv_obj_create`): a container or a rectangle.
    pub fn create(parent: Obj) -> Obj {
        Obj::from_ptr(unsafe { lv_obj_create(parent.as_ptr()) })
    }

    pub fn add_flag(self, flag: lv_obj_flag_t) {
        unsafe { lv_obj_add_flag(self.as_ptr(), flag) }
    }

    pub fn remove_flag(self, flag: lv_obj_flag_t) {
        unsafe { lv_obj_remove_flag(self.as_ptr(), flag) }
    }

    pub fn has_flag(self, flag: lv_obj_flag_t) -> bool {
        unsafe { lv_obj_has_flag(self.as_ptr(), flag) }
    }

    pub fn add_state(self, state: lv_state_t) {
        unsafe { lv_obj_add_state(self.as_ptr(), state) }
    }

    pub fn has_state(self, state: lv_state_t) -> bool {
        unsafe { lv_obj_has_state(self.as_ptr(), state) }
    }

    pub fn set_pos(self, x: i32, y: i32) {
        unsafe { lv_obj_set_pos(self.as_ptr(), x, y) }
    }

    /// Sizes in pixels, `lv_pct(..)` or `LV_SIZE_CONTENT`.
    pub fn set_size(self, width: i32, height: i32) {
        unsafe { lv_obj_set_size(self.as_ptr(), width, height) }
    }

    pub fn set_width(self, width: i32) {
        unsafe { lv_obj_set_width(self.as_ptr(), width) }
    }

    pub fn align(self, align: lv_align_t, x_offset: i32, y_offset: i32) {
        unsafe { lv_obj_align(self.as_ptr(), align, x_offset, y_offset) }
    }

    pub fn center(self) {
        unsafe { lv_obj_center(self.as_ptr()) }
    }

    /// Redraw the object at the next refresh (e.g. after changing a canvas's pixels).
    pub fn invalidate(self) {
        unsafe { lv_obj_invalidate(self.as_ptr()) };
    }

    /// Drop every style, including the theme's: start from a blank object.
    pub fn remove_style_all(self) {
        unsafe { lv_obj_remove_style_all(self.as_ptr()) }
    }

    /// Recompute how far the object draws outside its area (outlines, shadows).
    pub fn refresh_ext_draw_size(self) {
        unsafe { lv_obj_refresh_ext_draw_size(self.as_ptr()) }
    }

    /// Lay the children out in a row or column (`LV_FLEX_FLOW_*`).
    pub fn set_flex_flow(self, flow: lv_flex_flow_t) {
        unsafe { lv_obj_set_flex_flow(self.as_ptr(), flow) }
    }

    /// Where flex puts the children along the flow, across it, and the tracks (`LV_FLEX_ALIGN_*`).
    pub fn set_flex_align(self, main: lv_flex_align_t, cross: lv_flex_align_t, track_cross: lv_flex_align_t) {
        unsafe { lv_obj_set_flex_align(self.as_ptr(), main, cross, track_cross) }
    }

    /// In a flex parent: take this share of the free space (0 = only its own size).
    pub fn set_flex_grow(self, grow: u8) {
        unsafe { lv_obj_set_flex_grow(self.as_ptr(), grow) }
    }

    /// Give this object the keyboard focus in its group (`lv_group_focus_obj`).
    pub fn focus(self) {
        unsafe { lv_group_focus_obj(self.as_ptr()) }
    }

    /// The focus group the object is in (`lv_obj_get_group`).
    pub fn group(self) -> Option<Group> {
        NonNull::new(unsafe { lv_obj_get_group(self.as_ptr()) }).map(Group)
    }

    /// Take the object out of its focus group (`lv_group_remove_obj`).
    pub fn remove_from_group(self) {
        unsafe { lv_group_remove_obj(self.as_ptr()) }
    }

    /// Call `function(data)` when the object gets `code` (`lv_obj_add_event_cb`).
    pub fn on_event<T: 'static>(self, code: lv_event_code_t, data: &'static T, function: fn(&'static T)) {
        let user_data = Callback::leak(data, function);
        unsafe { lv_obj_add_event_cb(self.as_ptr(), event_trampoline::<T>, code, user_data) };
    }

    /// Call `function(data, event)` when the object gets `code`; for handlers
    /// that look at the event (its code, key or target, or to stop it). `code`
    /// may be `LV_EVENT_ALL` or include `LV_EVENT_PREPROCESS`.
    pub fn on_event_with<D: Copy + 'static>(self, code: lv_event_code_t, data: D, function: fn(D, &Event)) {
        let user_data = Box::leak(Box::new(EventHandler { data, function })) as *mut EventHandler<D> as *mut c_void;
        unsafe { lv_obj_add_event_cb(self.as_ptr(), event_handler_trampoline::<D>, code, user_data) };
    }

    /// `on_event_with` for a handler that needs only the event.
    pub fn on_event_fn(self, code: lv_event_code_t, function: fn(&Event)) {
        self.on_event_with(code, function, |function, event| function(event));
    }

    // Style properties (core/lv_obj_style_gen.h). `selector` is a part and/or
    // state, e.g. 0 (main part, default state) or LV_PART_KNOB | LV_STATE_FOCUSED.

    pub fn set_style_bg_color(self, color: lv_color_t, selector: lv_style_selector_t) {
        unsafe { lv_obj_set_style_bg_color(self.as_ptr(), color, selector) }
    }

    pub fn set_style_bg_opa(self, opa: lv_opa_t, selector: lv_style_selector_t) {
        unsafe { lv_obj_set_style_bg_opa(self.as_ptr(), opa, selector) }
    }

    pub fn set_style_border_width(self, width: i32, selector: lv_style_selector_t) {
        unsafe { lv_obj_set_style_border_width(self.as_ptr(), width, selector) }
    }

    /// `lv_obj_set_style_pad_hor` is a `static inline` C function: left and right padding.
    pub fn set_style_pad_hor(self, pad: i32, selector: lv_style_selector_t) {
        unsafe {
            lv_obj_set_style_pad_left(self.as_ptr(), pad, selector);
            lv_obj_set_style_pad_right(self.as_ptr(), pad, selector);
        }
    }

    /// `lv_obj_set_style_pad_ver` (`static inline` in C): top and bottom padding.
    pub fn set_style_pad_ver(self, pad: i32, selector: lv_style_selector_t) {
        unsafe {
            lv_obj_set_style_pad_top(self.as_ptr(), pad, selector);
            lv_obj_set_style_pad_bottom(self.as_ptr(), pad, selector);
        }
    }

    /// `lv_obj_set_style_pad_all` (`static inline` in C): padding on every side.
    pub fn set_style_pad_all(self, pad: i32, selector: lv_style_selector_t) {
        self.set_style_pad_hor(pad, selector);
        self.set_style_pad_ver(pad, selector);
    }

    /// The gap between the rows of a flex column (or wrapped rows).
    pub fn set_style_pad_row(self, pad: i32, selector: lv_style_selector_t) {
        unsafe { lv_obj_set_style_pad_row(self.as_ptr(), pad, selector) }
    }

    /// The gap between the children of a flex row.
    pub fn set_style_pad_column(self, pad: i32, selector: lv_style_selector_t) {
        unsafe { lv_obj_set_style_pad_column(self.as_ptr(), pad, selector) }
    }

    pub fn set_style_text_color(self, color: lv_color_t, selector: lv_style_selector_t) {
        unsafe { lv_obj_set_style_text_color(self.as_ptr(), color, selector) }
    }

    pub fn set_style_text_font(self, font: Font, selector: lv_style_selector_t) {
        unsafe { lv_obj_set_style_text_font(self.as_ptr(), font.0, selector) }
    }
}

impl Event {
    /// `LV_EVENT_CLICKED`, `LV_EVENT_KEY`, ... (without `LV_EVENT_PREPROCESS`).
    pub fn code(&self) -> lv_event_code_t {
        unsafe { lv_event_get_code(self.0.as_ptr()) }
    }

    /// For `LV_EVENT_KEY`: `LV_KEY_UP`, ... or the character the key types; 0 otherwise.
    pub fn key(&self) -> u32 {
        unsafe { lv_event_get_key(self.0.as_ptr()) }
    }

    /// The object the event was sent to.
    pub fn target(&self) -> Obj {
        Obj::from_ptr(unsafe { lv_event_get_target_obj(self.0.as_ptr()) })
    }

    /// Run no more handlers for this event: in a preprocess handler, not even
    /// the widget's own one.
    pub fn stop_processing(&self) {
        unsafe { lv_event_stop_processing(self.0.as_ptr()) }
    }
}

/// One type per widget: `Label::create(parent)` calls `lv_label_create`, the
/// widget's own functions are its methods, and everything in `Obj` works on it too.
macro_rules! widget {
    ($(#[$doc:meta])* $name:ident, $create:ident) => {
        $(#[$doc])*
        #[derive(Clone, Copy, Debug, PartialEq, Eq)]
        pub struct $name(Obj);

        impl $name {
            pub fn create(parent: Obj) -> $name {
                $name(Obj::from_ptr(unsafe { $create(parent.as_ptr()) }))
            }

            /// The widget as a plain object, e.g. to compare it with `Group::focused`.
            #[allow(dead_code)] // not every widget type needs it
            pub fn obj(self) -> Obj {
                self.0
            }
        }

        impl Deref for $name {
            type Target = Obj;

            fn deref(&self) -> &Obj {
                &self.0
            }
        }
    };
}

widget!(
    /// Text (`lv_label`).
    Label,
    lv_label_create
);
widget!(
    /// A picture (`lv_image`), e.g. a PNG from APPLaunch/share/images.
    Image,
    lv_image_create
);
widget!(
    /// A pixel buffer you draw into (`lv_canvas`).
    Canvas,
    lv_canvas_create
);
widget!(
    /// A clickable box (`lv_button`); put a `Label` inside for text.
    Button,
    lv_button_create
);
widget!(
    /// A text field (`lv_textarea`).
    Textarea,
    lv_textarea_create
);
widget!(
    /// A value on a track (`lv_slider`).
    Slider,
    lv_slider_create
);
widget!(
    /// A number with a digit format (`lv_spinbox`, a text area underneath).
    Spinbox,
    lv_spinbox_create
);
widget!(
    /// A button that opens a list of options (`lv_dropdown`).
    Dropdown,
    lv_dropdown_create
);
widget!(
    /// An on/off toggle (`lv_switch`); "on" is `LV_STATE_CHECKED`.
    Switch,
    lv_switch_create
);
widget!(
    /// A tick box with a text (`lv_checkbox`); ticked is `LV_STATE_CHECKED`.
    Checkbox,
    lv_checkbox_create
);

impl Label {
    pub fn set_text(self, text: &str) {
        unsafe { lv_label_set_text(self.as_ptr(), c_string(text).as_ptr()) }
    }
}

impl Image {
    /// Show an image file; `file_path` gives the path of one installed with the app.
    pub fn set_src_file(self, path: &str) {
        unsafe { lv_image_set_src(self.as_ptr(), c_string(path).as_ptr() as *const c_void) }
    }
}

impl Canvas {
    /// Draw from `pixels`, `width` x `height` RGB565 values, row by row. The
    /// buffer is `'static` because LVGL reads it whenever it redraws; `Cell`
    /// lets the app change pixels while LVGL holds the pointer.
    pub fn set_buffer_rgb565(self, pixels: &'static [Cell<u16>], width: i32, height: i32) {
        let needed = usize::try_from(width).unwrap_or(0) * usize::try_from(height).unwrap_or(0);
        assert!(pixels.len() >= needed, "canvas buffer too small");
        let buffer = pixels.as_ptr() as *mut c_void;
        unsafe { lv_canvas_set_buffer(self.as_ptr(), buffer, width, height, LV_COLOR_FORMAT_RGB565) }
    }
}

impl Textarea {
    pub fn set_one_line(self, enabled: bool) {
        unsafe { lv_textarea_set_one_line(self.as_ptr(), enabled) }
    }

    pub fn set_placeholder_text(self, text: &str) {
        unsafe { lv_textarea_set_placeholder_text(self.as_ptr(), c_string(text).as_ptr()) }
    }

    pub fn set_max_length(self, characters: u32) {
        unsafe { lv_textarea_set_max_length(self.as_ptr(), characters) }
    }

    pub fn text(self) -> String {
        let text = unsafe { lv_textarea_get_text(self.as_ptr()) };
        if text.is_null() {
            return String::new();
        }
        unsafe { CStr::from_ptr(text) }.to_string_lossy().into_owned()
    }
}

impl Slider {
    pub fn set_range(self, min: i32, max: i32) {
        unsafe { lv_slider_set_range(self.as_ptr(), min, max) }
    }

    pub fn set_value(self, value: i32, anim: lv_anim_enable_t) {
        unsafe { lv_slider_set_value(self.as_ptr(), value, anim) }
    }

    pub fn value(self) -> i32 {
        unsafe { lv_slider_get_value(self.as_ptr()) }
    }
}

impl Spinbox {
    pub fn set_range(self, min: i32, max: i32) {
        unsafe { lv_spinbox_set_range(self.as_ptr(), min, max) }
    }

    /// `digits` digits, with a decimal point after `separator` of them (0 = none).
    pub fn set_digit_format(self, digits: u32, separator: u32) {
        unsafe { lv_spinbox_set_digit_format(self.as_ptr(), digits, separator) }
    }

    /// Set the value; the spinbox sends LV_EVENT_VALUE_CHANGED.
    pub fn set_value(self, value: i32) {
        unsafe { lv_spinbox_set_value(self.as_ptr(), value) }
    }

    pub fn value(self) -> i32 {
        unsafe { lv_spinbox_get_value(self.as_ptr()) }
    }

    /// One step up (and LV_EVENT_VALUE_CHANGED).
    pub fn increment(self) {
        unsafe { lv_spinbox_increment(self.as_ptr()) }
    }

    /// One step down (and LV_EVENT_VALUE_CHANGED).
    pub fn decrement(self) {
        unsafe { lv_spinbox_decrement(self.as_ptr()) }
    }
}

impl Dropdown {
    /// The object as a dropdown, if it is one (`lv_obj_check_type`).
    pub fn cast(obj: Obj) -> Option<Dropdown> {
        unsafe { lv_obj_check_type(obj.as_ptr(), &lv_dropdown_class) }.then_some(Dropdown(obj))
    }

    /// `options`: one option per line ("Rust\nZig\nOCaml").
    pub fn set_options(self, options: &str) {
        unsafe { lv_dropdown_set_options(self.as_ptr(), c_string(options).as_ptr()) }
    }

    pub fn set_selected(self, index: u32) {
        unsafe { lv_dropdown_set_selected(self.as_ptr(), index) }
    }

    pub fn selected(self) -> u32 {
        unsafe { lv_dropdown_get_selected(self.as_ptr()) }
    }

    /// The selected option's text.
    pub fn selected_str(self) -> String {
        let mut buffer = [0 as c_char; 64];
        unsafe { lv_dropdown_get_selected_str(self.as_ptr(), buffer.as_mut_ptr(), buffer.len() as u32) };
        unsafe { CStr::from_ptr(buffer.as_ptr()) }.to_string_lossy().into_owned()
    }

    /// Whether the list of options is showing.
    pub fn is_open(self) -> bool {
        unsafe { lv_dropdown_is_open(self.as_ptr()) }
    }

    pub fn close(self) {
        unsafe { lv_dropdown_close(self.as_ptr()) }
    }
}

impl Checkbox {
    pub fn set_text(self, text: &str) {
        unsafe { lv_checkbox_set_text(self.as_ptr(), c_string(text).as_ptr()) }
    }
}

/// An LVGL timer: calls a function every `period` milliseconds while it runs.
#[derive(Clone, Copy, Debug)]
pub struct Timer(NonNull<lv_timer_t>);

impl Timer {
    /// Call `function(data)` every `period_ms` milliseconds (`lv_timer_create`).
    pub fn create<T: 'static>(period_ms: u32, data: &'static T, function: fn(&'static T)) -> Timer {
        let user_data = Callback::leak(data, function);
        let timer = unsafe { lv_timer_create(timer_trampoline::<T>, period_ms, user_data) };
        Timer(NonNull::new(timer).expect("LVGL could not create a timer"))
    }

    pub fn pause(self) {
        unsafe { lv_timer_pause(self.0.as_ptr()) }
    }

    pub fn resume(self) {
        unsafe { lv_timer_resume(self.0.as_ptr()) }
    }
}

/// A focus group (`lv_group_t`): the objects keyboard focus moves between.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Group(NonNull<lv_group_t>);

impl Group {
    pub fn create() -> Group {
        Group(NonNull::new(unsafe { lv_group_create() }).expect("LVGL could not create a group"))
    }

    /// Free the group; do not use this handle afterwards.
    pub fn delete(self) {
        unsafe { lv_group_delete(self.0.as_ptr()) }
    }

    /// Add `obj` (moving it out of any other group); focus moves in the order of these calls.
    pub fn add_obj(self, obj: Obj) {
        unsafe { lv_group_add_obj(self.0.as_ptr(), obj.as_ptr()) }
    }

    /// Let focus_next/focus_prev go from the last object to the first and back.
    pub fn set_wrap(self, enabled: bool) {
        unsafe { lv_group_set_wrap(self.0.as_ptr(), enabled) }
    }

    pub fn focus_next(self) {
        unsafe { lv_group_focus_next(self.0.as_ptr()) }
    }

    pub fn focus_prev(self) {
        unsafe { lv_group_focus_prev(self.0.as_ptr()) }
    }

    pub fn focused(self) -> Option<Obj> {
        NonNull::new(unsafe { lv_group_get_focused(self.0.as_ptr()) }).map(Obj)
    }
}

fn group_ptr(group: Option<Group>) -> *mut lv_group_t {
    group.map_or(ptr::null_mut(), |group| group.0.as_ptr())
}

/// An input device (`lv_indev_t`): the keypad, a mouse, ... A keypad sends its
/// keys to the focused object of its group.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Indev(NonNull<lv_indev_t>);

impl Indev {
    fn after(indev: Option<Indev>) -> Option<Indev> {
        let previous = indev.map_or(ptr::null_mut(), |indev| indev.0.as_ptr());
        NonNull::new(unsafe { lv_indev_get_next(previous) }).map(Indev)
    }

    /// Every input device (`lv_indev_get_next`).
    pub fn all() -> impl Iterator<Item = Indev> {
        std::iter::successors(Indev::after(None), |indev| Indev::after(Some(*indev)))
    }

    /// The device whose input LVGL is handling right now, if any (`lv_indev_active`).
    pub fn active() -> Option<Indev> {
        NonNull::new(unsafe { lv_indev_active() }).map(Indev)
    }

    /// `LV_INDEV_TYPE_KEYPAD`, ... (`lv_indev_get_type`).
    pub fn indev_type(self) -> lv_indev_type_t {
        unsafe { lv_indev_get_type(self.0.as_ptr()) }
    }

    /// The group a keypad sends its keys to.
    pub fn group(self) -> Option<Group> {
        NonNull::new(unsafe { lv_indev_get_group(self.0.as_ptr()) }).map(Group)
    }

    pub fn set_group(self, group: Option<Group>) {
        unsafe { lv_indev_set_group(self.0.as_ptr(), group_ptr(group)) }
    }

    /// Ignore the key or button that is down until it is released.
    pub fn wait_release(self) {
        unsafe { lv_indev_wait_release(self.0.as_ptr()) }
    }
}

// cp0_app: the app's page, keys and life cycle (cp0_app.h).

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum KeyState {
    Released,
    Pressed,
    /// Auto-repeat while the key is held down.
    Repeated,
}

/// One key event.
#[derive(Clone, Copy, Debug)]
pub struct Key<'a> {
    /// Linux key code: `keys::ESC`, `keys::ENTER`, `keys::F`, ...
    pub code: u32,
    pub state: KeyState,
    /// Modifier bits: 1 = Shift, 2 = Ctrl, 4 = Alt.
    #[allow(dead_code)] // this app does not need it
    pub mods: u32,
    /// The text the key types, with Shift and the symbol layer applied; "" if none.
    pub text: &'a str,
}

/// An app run by `run`: it gets every key event (releases included).
pub trait App: 'static {
    fn on_key(&self, key: &Key);
}

/// What `run` hands to cp0_app_run as user data.
struct Runner<A: App> {
    setup: fn(Obj) -> &'static A,
    app: Cell<Option<&'static A>>,
}

extern "C" fn setup_trampoline<A: App>(content: *mut lv_obj_t, user_data: *mut c_void) {
    let runner = unsafe { &*(user_data as *const Runner<A>) };
    runner.app.set(Some((runner.setup)(Obj::from_ptr(content))));
}

extern "C" fn key_trampoline<A: App>(key: *const cp0_app_key_t, user_data: *mut c_void) {
    let runner = unsafe { &*(user_data as *const Runner<A>) };
    let (Some(app), Some(key)) = (runner.app.get(), unsafe { key.as_ref() }) else {
        return;
    };
    let text = if key.text.is_null() { c"" } else { unsafe { CStr::from_ptr(key.text) } };
    let state = match key.state {
        0 => KeyState::Released,
        2 => KeyState::Repeated,
        _ => KeyState::Pressed,
    };
    app.on_key(&Key { code: key.code, state, mods: key.mods, text: text.to_str().unwrap_or("") });
}

/// Run the app: set up LVGL, the display (SDL window, fbsim framebuffer or the
/// device panel), the keyboard and the top bar titled `title`, call
/// `setup(content)` to build the UI on the 320x150 content area, then deliver
/// keys to the app until `quit`. Returns the exit status.
pub fn run<A: App>(title: &str, setup: fn(Obj) -> &'static A) -> i32 {
    let runner = Runner { setup, app: Cell::new(None) };
    let user_data = &runner as *const Runner<A> as *mut c_void;
    let title = c_string(title);
    unsafe { cp0_app_run(title.as_ptr(), setup_trampoline::<A>, Some(key_trampoline::<A>), user_data) }
}

/// Leave the event loop; `run` returns soon after.
pub fn quit() {
    unsafe { cp0_app_quit() }
}

/// The top bar's title.
pub fn set_title(title: &str) {
    unsafe { cp0_app_set_title(c_string(title).as_ptr()) }
}

/// `true`: keys type text (F/X/Z/C are letters). `false` (the default): F/X/Z/C
/// also act as up/down/left/right, like in the launcher.
pub fn set_text_input(enabled: bool) {
    unsafe { cp0_app_set_text_input(c_int::from(enabled)) }
}

/// Path of a file installed with the app (`APPLaunch/share/images/<name>`, ...)
/// that LVGL can open, on the desktop and the device alike.
pub fn file_path(name: &str) -> String {
    let name = c_string(name);
    let length = unsafe { cp0_app_file_path(name.as_ptr(), ptr::null_mut(), 0) };
    let mut buffer = vec![0u8; length + 1];
    unsafe { cp0_app_file_path(name.as_ptr(), buffer.as_mut_ptr() as *mut c_char, buffer.len()) };
    buffer.truncate(length);
    String::from_utf8_lossy(&buffer).into_owned()
}
