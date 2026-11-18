// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! Demo 4, widgets: a form of stock LVGL widgets with the default theme, laid out with
//! flex and driven by LVGL's own focus group and widget events: lv_textarea, lv_button,
//! lv_slider, lv_spinbox, lv_dropdown, lv_switch, lv_checkbox. F/X move the focus, Z/C
//! change the value, ENTER presses; the text area takes typing.
//!
//! Stock LVGL, plus one adapter for the keyboard
//! ---------------------------------------------
//! Everything on this screen is plain LVGL:
//!   - the look is LVGL's default theme (ui.setTheme(), which main.zig's setup() calls
//!     before any widget exists). The widgets get sizes, never colors; the Color row runs
//!     the theme again with another accent color and every widget follows;
//!   - the layout is flex: a scrolling column of rows, each a label and widgets;
//!   - the focus is an lv_group holding the form's widgets, which the keypad input device
//!     uses while the screen shows. The focused widget gets LV_STATE_FOCUS_KEY (the theme
//!     draws an outline) and scrolls into view;
//!   - cp0_lvgl delivers every key twice: first to the cp0_app key callback (main.zig's
//!     onKey; this screen uses it only for ESC and TAB), then through LVGL's keypad
//!     input device to the focused widget as LV_EVENT_KEY: arrows (F/X/Z/C
//!     on the CardputerZero), ENTER, ESC, BACKSPACE ... as LVGL's keys, and the character
//!     for a key that types one. Each widget reacts the way it always does: the text area
//!     takes typing and BACKSPACE, DEL, LEFT/RIGHT, HOME/END; ENTER clicks a button,
//!     toggles the switch and the checkbox, opens the dropdown and picks an option;
//!     LEFT/RIGHT move the slider; ESC closes the dropdown;
//!   - the form reacts only to widget events (LV_EVENT_CLICKED, LV_EVENT_VALUE_CHANGED,
//!     LV_EVENT_READY), so a mouse click in the simulator window does exactly what the
//!     keys do.
//!
//! The CardputerZero keyboard needs one small adapter and one switch on top:
//!   - Moving the focus. LVGL moves it only on LV_KEY_NEXT/LV_KEY_PREV, which the keyboard
//!     never sends; it has no arrow keys either, so cp0_lvgl turns F/X/Z/C into
//!     UP/DOWN/LEFT/RIGHT. focusKeysCb, an LV_EVENT_KEY preprocess handler on every widget
//!     of the form, turns UP/DOWN into lv_group_focus_prev/next, except while the
//!     dropdown's list is open (there UP/DOWN choose an option). (countKeysCb gives the
//!     spinbox's LEFT/RIGHT, which would move between digits, to its value.)
//!   - Typing. While the text area has the focus the keyboard is in text mode
//!     (cp0_app_set_text_input), so F/X/Z/C type letters instead of acting as arrows.

const std = @import("std");
const c = @import("lvgl.zig");
const ui = @import("ui.zig");

const Action = ui.Action;

const form_top = 18; // below the status line
const label_width = 62; // the column of row labels
const max_name = 24;
const form_hint = "F/X move  Z/C change  ENTER press";
const typing_hint = "type a name  ENTER next";

const Choice = struct {
    name: []const u8,
    color: u32,
};

/// The Color row: each template's language and GitHub's color for it, in the dropdown's
/// order.
const choices = [_]Choice{
    .{ .name = "Rust", .color = 0xDEA584 },
    .{ .name = "Zig", .color = 0xEC915C },
    .{ .name = "OCaml", .color = 0xEF7A08 },
    .{ .name = "C++", .color = 0xF34B7D },
};

/// The dropdown's options, one per line.
const choice_options = blk: {
    var options: [:0]const u8 = "";
    for (choices, 0..) |choice, index| options = options ++ (if (index == 0) "" else "\n") ++ choice.name;
    break :blk options;
};

/// This template starts on its own language, Zig.
const language_choice: u32 = blk: {
    for (choices, 0..) |choice, index| {
        if (std.mem.eql(u8, choice.name, ui.language)) break :blk index;
    }
    @compileError("ui.language is not one of the choices");
};

const key_preprocess = c.preprocess(.key);

/// One row of the form: a transparent flex row holding a fixed-width label; the caller
/// adds the row's widgets after it.
fn makeRow(form: *c.Obj, text: [*:0]const u8) *c.Obj {
    const row = c.lv_obj_create(form);
    c.lv_obj_remove_style_all(row); // layout only: no background, border or padding
    c.lv_obj_set_size(row, c.pct(100), c.size_content);
    c.lv_obj_set_flex_flow(row, .row);
    c.lv_obj_set_flex_align(row, .start, .center, .center);
    c.setPadAll(row, 4, 0); // room for the theme's focus outline around the widgets
    c.lv_obj_set_style_pad_column(row, 6, 0);
    const label = c.lv_label_create(row);
    c.lv_label_set_text(label, text);
    c.lv_obj_set_width(label, label_width);
    return row;
}

/// The default theme pads widgets for bigger screens. On 320 x 150 the form trims the
/// vertical padding of the taller widgets to fit more rows.
fn compact(widget: *c.Obj) void {
    c.setPadVer(widget, 4, 0);
}

fn makeButton(parent: *c.Obj, text: [*:0]const u8) *c.Obj {
    const button = c.lv_button_create(parent);
    compact(button);
    const label = c.lv_label_create(button);
    c.lv_label_set_text(label, text);
    c.lv_obj_center(label);
    return button;
}

/// The adapter: F/X (UP/DOWN) move the focus to the previous/next widget.
fn focusKeysCb(event: *c.Event) callconv(.c) void {
    const key = c.lv_event_get_key(event);
    if (key != c.lv_key.up and key != c.lv_key.down) return;
    const widget = c.lv_event_get_target_obj(event);
    if (c.lv_obj_check_type(widget, &c.lv_dropdown_class) and c.lv_dropdown_is_open(widget)) return;
    const group = c.lv_obj_get_group(widget) orelse return;
    if (key == c.lv_key.up) c.lv_group_focus_prev(group) else c.lv_group_focus_next(group);
    c.lv_event_stop_processing(event); // the widget itself never sees the key
}

/// Z/C (LEFT/RIGHT) step the spinbox's value; nothing else edits it (typed characters
/// included: the spinbox is a text area underneath).
fn countKeysCb(event: *c.Event) callconv(.c) void {
    const spinbox = c.lv_event_get_target_obj(event);
    const key = c.lv_event_get_key(event);
    if (key == c.lv_key.up or key == c.lv_key.down) return; // focus moves
    if (key == c.lv_key.left) c.lv_spinbox_decrement(spinbox) else if (key == c.lv_key.right) c.lv_spinbox_increment(spinbox);
    c.lv_event_stop_processing(event);
}

/// ENTER in the one-line text area: on to the next widget. The ENTER key is still down;
/// waiting for its release keeps it from clicking the newly focused button.
fn nameReadyCb(event: *c.Event) callconv(.c) void {
    const group = c.lv_obj_get_group(c.lv_event_get_target_obj(event)) orelse return;
    c.lv_group_focus_next(group);
    if (c.lv_indev_active()) |keypad| c.lv_indev_wait_release(keypad);
}

/// The spinbox's -/+ buttons, as in LVGL's spinbox example: a click steps once, holding
/// the mouse button repeats.
fn isStepEvent(event: *c.Event) bool {
    const code = c.lv_event_get_code(event);
    return code == .short_clicked or code == .long_pressed_repeat;
}

fn minusCb(event: *c.Event) callconv(.c) void {
    if (isStepEvent(event)) c.lv_spinbox_decrement(c.eventUserData(c.Obj, event));
}

fn plusCb(event: *c.Event) callconv(.c) void {
    if (isStepEvent(event)) c.lv_spinbox_increment(c.eventUserData(c.Obj, event));
}

/// The -/+ buttons are for the mouse: Z/C do the same from the keyboard. Keep them out of
/// every focus group (lv_button_create adds a button to the default group, if there is one).
fn makeStepButton(row: *c.Obj, text: [*:0]const u8) *c.Obj {
    const button = makeButton(row, text);
    c.lv_group_remove_obj(button);
    return button;
}

/// The app ends by deleting the page, and the root object gets LV_EVENT_DELETE before its
/// children are deleted. Deleting the group then means that deleting the focused widget
/// moves no focus, so no focus callback runs on widgets that are already gone.
fn rootDeletedCb(event: *c.Event) callconv(.c) void {
    c.lv_group_delete(c.eventUserData(c.Group, event));
}

pub const Widgets = struct {
    screen: ui.Screen,
    group: *c.Group = undefined, // the form's focusable widgets, in F/X order
    previous_group: ?*c.Group = null, // the keypad's group before this screen showed
    status: *c.Obj = undefined,
    form: *c.Obj = undefined, // the scrolling column of rows
    hint: *c.Obj = undefined,
    name: *c.Obj = undefined,
    volume: *c.Obj = undefined,
    volume_value: *c.Obj = undefined,
    count: *c.Obj = undefined,
    color: *c.Obj = undefined,
    sound: *c.Obj = undefined,
    sound_value: *c.Obj = undefined,
    like: *c.Obj = undefined,

    pub fn title(_: *const Widgets) [*:0]const u8 {
        return "Widgets";
    }

    fn setStatus(self: *Widgets, comptime format: []const u8, args: anytype) void {
        var text: [64]u8 = undefined;
        c.setText(self.status, std.fmt.bufPrint(&text, format, args) catch unreachable);
    }

    /// The text area has the focus: keys type text, and the hint says so.
    fn setTyping(self: *Widgets, typing: bool) void {
        c.lv_label_set_text(self.hint, if (typing) typing_hint else form_hint);
        if (self.screen.shown()) c.cp0_app_set_text_input(@intFromBool(typing));
    }

    fn nameFocusCb(event: *c.Event) callconv(.c) void {
        c.eventUserData(Widgets, event).setTyping(c.lv_event_get_code(event) == .focused);
    }

    fn helloClickedCb(event: *c.Event) callconv(.c) void {
        const self = c.eventUserData(Widgets, event);
        const name = std.mem.trim(u8, std.mem.span(c.lv_textarea_get_text(self.name)), " \t");
        self.setStatus("Hello, {s}!", .{if (name.len == 0) "stranger" else name});
    }

    fn addOneClickedCb(event: *c.Event) callconv(.c) void {
        const count = c.eventUserData(Widgets, event).count;
        c.lv_spinbox_set_value(count, c.lv_spinbox_get_value(count) + 1); // the spinbox reports the change
    }

    fn volumeChangedCb(event: *c.Event) callconv(.c) void {
        const self = c.eventUserData(Widgets, event);
        var number: [16]u8 = undefined;
        const value = std.fmt.bufPrint(&number, "{d}", .{c.lv_slider_get_value(self.volume)}) catch unreachable;
        c.setText(self.volume_value, value);
        self.setStatus("Volume {s}", .{value});
    }

    fn countChangedCb(event: *c.Event) callconv(.c) void {
        const self = c.eventUserData(Widgets, event);
        self.setStatus("Count {d}", .{c.lv_spinbox_get_value(self.count)});
    }

    fn colorChangedCb(event: *c.Event) callconv(.c) void {
        const self = c.eventUserData(Widgets, event);
        const choice = choices[c.lv_dropdown_get_selected(self.color)];
        ui.setTheme(choice.color); // every themed widget in the app takes the new accent color
        c.lv_obj_set_style_text_color(self.status, c.color(choice.color), 0);
        self.setStatus("Color {s}", .{choice.name});
    }

    fn soundChangedCb(event: *c.Event) callconv(.c) void {
        const self = c.eventUserData(Widgets, event);
        const on_off: [:0]const u8 = if (c.lv_obj_has_state(self.sound, c.state.checked)) "on" else "off";
        c.lv_label_set_text(self.sound_value, on_off);
        self.setStatus("Sound {s}", .{on_off});
    }

    fn likeChangedCb(event: *c.Event) callconv(.c) void {
        const self = c.eventUserData(Widgets, event);
        self.setStatus("{s}", .{if (c.lv_obj_has_state(self.like, c.state.checked)) "Thanks!" else "Oh no"});
    }

    /// Every focusable widget: into the group (F/X order is the order of these calls), the
    /// adapter for F/X, and scrolled into view when it gets the focus.
    fn addToForm(self: *Widgets, widget: *c.Obj) void {
        c.lv_group_add_obj(self.group, widget);
        c.onEvent(widget, key_preprocess, focusKeysCb, null);
        c.lv_obj_add_flag(widget, c.obj_flag.scroll_on_focus);
    }

    fn makeNameRow(self: *Widgets) void {
        const row = makeRow(self.form, "Name");
        const name = c.lv_textarea_create(row);
        self.name = name;
        c.lv_textarea_set_one_line(name, true);
        c.lv_textarea_set_placeholder_text(name, "your name");
        c.lv_textarea_set_max_length(name, max_name);
        c.lv_obj_set_flex_grow(name, 1);
        compact(name);
        self.addToForm(name);
        c.onEvent(name, .focused, nameFocusCb, self);
        c.onEvent(name, .defocused, nameFocusCb, self);
        c.onEvent(name, .ready, nameReadyCb, null);
    }

    fn makeButtonsRow(self: *Widgets) void {
        const row = makeRow(self.form, "Buttons");
        const hello = makeButton(row, "Say hello");
        self.addToForm(hello);
        c.onEvent(hello, .clicked, helloClickedCb, self);
        const add_one = makeButton(row, "Count +1");
        self.addToForm(add_one);
        c.onEvent(add_one, .clicked, addOneClickedCb, self);
    }

    fn makeVolumeRow(self: *Widgets) void {
        const row = makeRow(self.form, "Volume");
        const volume = c.lv_slider_create(row);
        self.volume = volume;
        c.lv_slider_set_range(volume, 0, 100);
        c.lv_slider_set_value(volume, 50, c.anim_off);
        c.lv_obj_set_flex_grow(volume, 1);
        self.addToForm(volume);
        c.onEvent(volume, .value_changed, volumeChangedCb, self);
        self.volume_value = c.lv_label_create(row);
        c.lv_label_set_text(self.volume_value, "50");
        c.lv_obj_set_width(self.volume_value, 30);
    }

    fn makeCountRow(self: *Widgets) void {
        const row = makeRow(self.form, "Count");
        const minus = makeStepButton(row, "-");
        const count = c.lv_spinbox_create(row);
        self.count = count;
        c.lv_spinbox_set_range(count, -999, 999);
        c.lv_spinbox_set_digit_format(count, 3, 0);
        c.lv_obj_set_width(count, 64);
        compact(count);
        self.addToForm(count);
        c.onEvent(count, key_preprocess, countKeysCb, null);
        c.onEvent(count, .value_changed, countChangedCb, self);
        const plus = makeStepButton(row, "+");
        c.onEvent(minus, .all, minusCb, count);
        c.onEvent(plus, .all, plusCb, count);
    }

    fn makeColorRow(self: *Widgets) void {
        const row = makeRow(self.form, "Color");
        const color = c.lv_dropdown_create(row);
        self.color = color;
        c.lv_dropdown_set_options(color, choice_options);
        c.lv_dropdown_set_selected(color, language_choice);
        c.lv_obj_set_width(color, 100);
        compact(color);
        self.addToForm(color);
        c.onEvent(color, .value_changed, colorChangedCb, self);
    }

    fn makeSoundRow(self: *Widgets) void {
        const row = makeRow(self.form, "Sound");
        const sound = c.lv_switch_create(row);
        self.sound = sound;
        c.lv_obj_add_state(sound, c.state.checked);
        self.addToForm(sound);
        c.onEvent(sound, .value_changed, soundChangedCb, self);
        self.sound_value = c.lv_label_create(row);
        c.lv_label_set_text(self.sound_value, "on");
    }

    fn makeLikeRow(self: *Widgets) void {
        const row = makeRow(self.form, "Like");
        const like = c.lv_checkbox_create(row);
        self.like = like;
        c.lv_checkbox_set_text(like, "I like LVGL");
        self.addToForm(like);
        c.onEvent(like, .value_changed, likeChangedCb, self);
    }

    /// `self` must not move afterwards: LVGL callbacks hold pointers to it.
    pub fn init(self: *Widgets, parent: *c.Obj) void {
        self.* = .{ .screen = .init(parent) };
        const root = self.screen.root;
        self.status = ui.makeLabel(root, "Try every widget", &c.lv_font_montserrat_14, ui.language_color);
        c.lv_obj_set_pos(self.status, 8, 0);
        _ = ui.makeDemoKeys(root);

        // The form: a flex column that scrolls when the rows don't fit. It keeps the
        // theme's scrollbar but not its card background.
        const form = c.lv_obj_create(root);
        self.form = form;
        c.lv_obj_set_pos(form, 0, form_top);
        c.lv_obj_set_size(form, ui.content_width, ui.hint_top - form_top);
        c.lv_obj_set_style_bg_opa(form, c.opa_transp, 0);
        c.lv_obj_set_style_border_width(form, 0, 0);
        c.setPadAll(form, 2, 0);
        c.lv_obj_set_style_pad_row(form, 0, 0);
        c.lv_obj_set_flex_flow(form, .column);

        self.hint = ui.makeHint(root, form_hint);

        self.group = c.lv_group_create();
        c.lv_group_set_wrap(self.group, true); // X on the last widget goes back to the first
        c.onEvent(root, .delete, rootDeletedCb, self.group);

        // The rows, top to bottom; F/X visit their widgets in this order.
        self.makeNameRow();
        self.makeButtonsRow();
        self.makeVolumeRow();
        self.makeCountRow();
        self.makeColorRow();
        self.makeSoundRow();
        self.makeLikeRow();
    }

    pub fn onShow(self: *Widgets) void {
        // The keypad input device(s) use the form's group while the screen shows. The key
        // that opened the screen (4, ENTER, TAB) is still being handled:
        // lv_indev_wait_release keeps it from reaching the focused widget (ENTER would
        // leave the text area, 4 would be typed into it).
        var next = c.lv_indev_get_next(null);
        while (next) |indev| : (next = c.lv_indev_get_next(indev)) {
            if (c.lv_indev_get_type(indev) != .keypad) continue;
            self.previous_group = c.lv_indev_get_group(indev);
            c.lv_indev_set_group(indev, self.group);
            c.lv_indev_wait_release(indev);
        }
        // Focus a widget, now from the keypad, so it gets LV_STATE_FOCUS_KEY (the theme's
        // outline) and its LV_EVENT_FOCUSED handlers run: the one that had the focus, or
        // the first time the first one (hidden widgets can't take the focus, so none has
        // it yet).
        if (c.lv_group_get_focused(self.group)) |focused| c.lv_group_focus_obj(focused) else c.lv_group_focus_next(self.group);
        // LVGL 9.5 does not grow the drawing area of a widget that was never drawn when its
        // new state also changes its layout, as the text area's cursor style does; without
        // this the first outline would be clipped away.
        if (c.lv_group_get_focused(self.group)) |focused| c.lv_obj_refresh_ext_draw_size(focused);
    }

    pub fn onHide(self: *Widgets) void {
        c.lv_dropdown_close(self.color); // its list belongs to the LVGL screen, not to this container
        var next = c.lv_indev_get_next(null);
        while (next) |indev| : (next = c.lv_indev_get_next(indev)) {
            if (c.lv_indev_get_group(indev) == self.group) c.lv_indev_set_group(indev, self.previous_group);
        }
        c.cp0_app_set_text_input(0);
    }

    pub fn handleKey(self: *Widgets, key: *const c.Key) Action {
        // Only the app's keys; LVGL's keypad device delivers every key to the focused
        // widget as well. ESC first closes an open dropdown list: LVGL gets the same ESC
        // right after this and closes it.
        return switch (key.code) {
            ui.keys.esc => if (c.lv_dropdown_is_open(self.color)) .stay else .home,
            ui.keys.tab => .next,
            else => .stay,
        };
    }
};
