// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! The app's look and plumbing, shared by every screen: colors, key helpers,
//! label/panel helpers and `Screen`, the part every screen is built on.

const c = @import("lvgl.zig");

/// The language this template is written in, and GitHub's color for it.
pub const language = "Zig";
pub const language_color: u32 = 0xEC915C;

pub const background_color: u32 = 0x0E1217;
pub const text_color: u32 = 0xFFFFFF;
pub const muted_color: u32 = 0x96A0AA;
pub const error_color: u32 = 0xFF6E6E;

/// The content area below the 20 px top bar, which every screen fills.
pub const content_width = 320;
pub const content_height = 150;
/// Top of the key-help line at the bottom of a screen (content coordinates).
pub const hint_top = content_height - 17;
/// Animation frame period: about 60 frames per second.
pub const frame_ms: u32 = 16;

/// What a screen asks the app to do after a key press.
pub const Action = union(enum) {
    stay,
    /// Back to the home screen.
    home,
    /// On to the next demo (TAB).
    next,
    /// Open demo number N (0-based) from the home screen.
    open: usize,
    quit,
};

/// Linux key codes (linux/input-event-codes.h) of the keys the app uses.
pub const keys = struct {
    pub const esc = 1;
    pub const digit_1 = 2;
    pub const digit_2 = 3;
    pub const digit_3 = 4;
    pub const digit_4 = 5;
    pub const backspace = 14;
    pub const tab = 15;
    pub const enter = 28;
    pub const letter_f = 33;
    pub const letter_z = 44;
    pub const letter_x = 45;
    pub const letter_c = 46;
    pub const space = 57;
    pub const up = 103;
    pub const left = 105;
    pub const right = 106;
    pub const down = 108;
};

pub const Direction = enum { up, down, left, right };

/// The CardputerZero keyboard has no arrow keys: like the launcher, F/X/Z/C act as
/// up/down/left/right. Real arrow keys (simulator, USB keyboards) work too.
pub fn direction(code: u32) ?Direction {
    return switch (code) {
        keys.up, keys.letter_f => .up,
        keys.down, keys.letter_x => .down,
        keys.left, keys.letter_z => .left,
        keys.right, keys.letter_c => .right,
        else => null,
    };
}

/// The character the key typed (cp0_lvgl applies Shift and the symbol layer), or null
/// for keys that type nothing printable.
pub fn typedText(key: *const c.Key) ?[]const u8 {
    const text = key.typed();
    return if (text.len == 1 and text[0] >= 0x20 and text[0] < 0x7F) text else null;
}

pub fn makeLabel(parent: *c.Obj, text: [*:0]const u8, font: *const c.Font, color: u32) *c.Obj {
    const label = c.lv_label_create(parent);
    c.lv_label_set_text(label, text);
    c.lv_obj_set_style_text_font(label, font, 0);
    c.lv_obj_set_style_text_color(label, c.color(color), 0);
    return label;
}

/// A plain rectangle; `opa` below c.opa_cover shades what is under it.
pub fn makePanel(parent: *c.Obj, x: i32, y: i32, width: i32, height: i32, color: u32, opa: u8) *c.Obj {
    const panel = c.lv_obj_create(parent);
    c.lv_obj_remove_style_all(panel);
    c.lv_obj_set_pos(panel, x, y);
    c.lv_obj_set_size(panel, width, height);
    c.lv_obj_set_style_bg_color(panel, c.color(color), 0);
    c.lv_obj_set_style_bg_opa(panel, opa, 0);
    c.lv_obj_remove_flag(panel, c.obj_flag.clickable | c.obj_flag.scrollable);
    return panel;
}

/// One line of key help, centered at the bottom of a screen.
pub fn makeHint(parent: *c.Obj, text: [*:0]const u8) *c.Obj {
    const hint = makeLabel(parent, text, &c.lv_font_montserrat_14, muted_color);
    c.lv_obj_align(hint, .top_mid, 0, hint_top);
    return hint;
}

/// "TAB next  ESC home", top right: how to leave a demo.
pub fn makeDemoKeys(parent: *c.Obj) *c.Obj {
    const demo_keys = makeLabel(parent, "TAB next  ESC home", &c.lv_font_montserrat_12, muted_color);
    c.lv_obj_align(demo_keys, .top_right, -6, 2);
    return demo_keys;
}

/// The part every screen is built on: a full-size container in the content area
/// that shows while the screen is active, and an optional frame timer. Each screen
/// struct has one as its `screen` field; main.zig shows and hides them.
pub const Screen = struct {
    root: *c.Obj,
    timer: ?*c.Timer = null,

    pub fn init(parent: *c.Obj) Screen {
        const root = makePanel(parent, 0, 0, content_width, content_height, background_color, c.opa_cover);
        c.setHidden(root, true);
        return .{ .root = root };
    }

    /// The app ends by deleting the page: stop the timer before the widgets go.
    fn rootDeletedCb(event: *c.Event) callconv(.c) void {
        const self = c.eventUserData(Screen, event);
        if (self.timer) |timer| c.lv_timer_delete(timer);
        self.timer = null;
    }

    /// Call `owner.onFrame()` every frame_ms while the screen shows. `owner` is the
    /// screen struct this Screen belongs to; neither may move afterwards.
    pub fn animate(self: *Screen, comptime Owner: type, owner: *Owner) void {
        if (self.timer != null) return;
        const frame = struct {
            fn run(timer: *c.Timer) callconv(.c) void {
                c.timerUserData(Owner, timer).onFrame();
            }
        }.run;
        const timer = c.lv_timer_create(frame, frame_ms, owner);
        c.lv_timer_pause(timer);
        self.timer = timer;
        c.onEvent(self.root, .delete, rootDeletedCb, self);
    }

    pub fn show(self: *Screen) void {
        c.setHidden(self.root, false);
        if (self.timer) |timer| c.lv_timer_resume(timer);
    }

    pub fn hide(self: *Screen) void {
        if (self.timer) |timer| c.lv_timer_pause(timer);
        c.setHidden(self.root, true);
    }

    pub fn shown(self: *const Screen) bool {
        return !c.lv_obj_has_flag(self.root, c.obj_flag.hidden);
    }
};
