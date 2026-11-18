// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! Demo 4, widgets: a small form of real LVGL widgets (lv_textarea, lv_button,
//! lv_slider, a -/+ counter, lv_roller, lv_switch) in an lv_group. F/X move the focus,
//! Z/C change the value, ENTER presses; the text field takes typing.
//!
//! How keys reach the widgets
//! --------------------------
//! cp0_lvgl delivers every key twice: first to the cp0_app key callback (main.zig's
//! onKey: the Linux key code and the text it types), then through LVGL's keypad input
//! device to the focused object of the page's lv_group, as LV_EVENT_KEY. That second
//! path cannot drive a form on the CardputerZero: the keyboard has no arrow keys
//! (F/X/Z/C turn into arrows, so they could not be typed into the text field), letters
//! arrive as key codes rather than characters, and LVGL only moves the focus on
//! LV_KEY_NEXT/LV_KEY_PREV, which the keyboard never sends.
//!
//! So while this screen shows it turns that path off (cp0_app_set_keypad_intercept)
//! and handles the key callback itself, using LVGL's own machinery for the rest:
//!   - the widgets sit in an lv_group: F/X call lv_group_focus_prev/next, and the
//!     focused widget gets LV_STATE_FOCUSED, which its styles react to;
//!   - Z/C and ENTER set the focused widget's value through its API and send the event
//!     LVGL itself would send (LV_EVENT_VALUE_CHANGED, LV_EVENT_CLICKED);
//!   - the form reacts to those events only, so a mouse click in the simulator window
//!     (or a touch screen) works the same way as the keys;
//!   - typed text goes into the lv_textarea with lv_textarea_add_text, and the keyboard
//!     is in text mode (cp0_app_set_text_input) while the text field has the focus.
//! The same works on the device and on the desktop.

const std = @import("std");
const c = @import("lvgl.zig");
const ui = @import("ui.zig");

const Action = ui.Action;

const field_color: u32 = 0x080A0E;
const border_color: u32 = 0x3C4652;
const face_color: u32 = 0x1C222A;

/// The form's rows, top to bottom; the status line sits above them.
const Row = enum { name, button, volume, count, color, sound };
const row_labels = [_][*:0]const u8{ "Name", "Button", "Volume", "Count", "Color", "Sound" };
const row_count = row_labels.len;
const rows_top = 18;
const row_height = 18;
const widget_left = 72; // labels on the left, widgets from here
const widget_width = 242;
const slider_width = 176;
const volume_step = 5;
const max_name = 24;
const press_ms = 10 * ui.frame_ms; // how long the button shows as pressed

const Choice = struct {
    name: []const u8,
    color: u32,
};

/// The chooser's options: each template language and GitHub's color for it.
const choices = [_]Choice{
    .{ .name = "Rust", .color = 0xDEA584 },
    .{ .name = "Zig", .color = 0xEC915C },
    .{ .name = "OCaml", .color = 0xEF7A08 },
    .{ .name = "C++", .color = 0xF34B7D },
};

/// The roller's options, one per line.
const choice_options = blk: {
    var options: [:0]const u8 = "";
    for (choices, 0..) |choice, index| options = options ++ (if (index == 0) "" else "\n") ++ choice.name;
    break :blk options;
};

fn defaultChoice() u32 {
    for (choices, 0..) |choice, index| {
        if (std.mem.eql(u8, choice.name, ui.language)) return @intCast(index);
    }
    return 0;
}

/// The form's widgets are styled from scratch (no theme), flat like the rest of the app.
fn styleBox(obj: *c.Obj, background: u32) void {
    c.lv_obj_set_style_bg_color(obj, c.color(background), 0);
    c.lv_obj_set_style_bg_opa(obj, c.opa_cover, 0);
    c.lv_obj_set_style_border_width(obj, 1, 0);
    c.lv_obj_set_style_border_color(obj, c.color(border_color), 0);
    c.lv_obj_set_style_text_font(obj, &c.lv_font_montserrat_14, 0);
    c.lv_obj_set_style_text_color(obj, c.color(ui.text_color), 0);
}

fn makeBoxButton(parent: *c.Obj, text: [*:0]const u8, x: i32, y: i32, width: i32) *c.Obj {
    const button = c.lv_button_create(parent);
    c.lv_obj_remove_style_all(button);
    styleBox(button, face_color);
    c.lv_obj_set_pos(button, x, y);
    c.lv_obj_set_size(button, width, row_height);
    const label = c.lv_label_create(button);
    c.lv_label_set_text(label, text);
    c.lv_obj_center(label);
    return button;
}

pub const Widgets = struct {
    screen: ui.Screen,
    group: *c.Group = undefined,
    bars: [row_count]*c.Obj = undefined,
    labels: [row_count]*c.Obj = undefined,
    widgets: [row_count]*c.Obj = undefined, // the focusable object of each row
    name: *c.Obj = undefined,
    button: *c.Obj = undefined,
    volume: *c.Obj = undefined,
    volume_value: *c.Obj = undefined,
    counter: *c.Obj = undefined,
    minus: *c.Obj = undefined,
    plus: *c.Obj = undefined,
    count_value: *c.Obj = undefined,
    chooser: *c.Obj = undefined,
    chooser_left: *c.Obj = undefined,
    chooser_right: *c.Obj = undefined,
    swatch: *c.Obj = undefined,
    sound: *c.Obj = undefined,
    sound_value: *c.Obj = undefined,
    status: *c.Obj = undefined,
    hint: *c.Obj = undefined,
    release_timer: ?*c.Timer = null,
    count: i32 = 0,

    pub fn title(_: *const Widgets) [*:0]const u8 {
        return "Widgets";
    }

    fn accent(self: *const Widgets) u32 {
        return choices[c.lv_roller_get_selected(self.chooser)].color;
    }

    fn setStatus(self: *Widgets, text: []const u8) void {
        c.setText(self.status, text);
    }

    fn setCount(self: *Widgets, count: i32, status: []const u8) void {
        self.count = count;
        var number: [16]u8 = undefined;
        c.setText(self.count_value, std.fmt.bufPrint(&number, "{d}", .{count}) catch unreachable);
        self.setStatus(status);
    }

    /// The row markers that are not LVGL focus styles: accent bar, label colors, counter
    /// and chooser decorations, the hint, and the keyboard mode.
    fn refreshFocus(self: *Widgets) void {
        const focused = c.lv_group_get_focused(self.group);
        const accent_color = c.color(self.accent());
        for (self.widgets, self.bars, self.labels) |widget, bar, label| {
            const is_focused = focused == widget;
            c.setHidden(bar, !is_focused);
            c.lv_obj_set_style_text_color(label, if (is_focused) accent_color else c.color(ui.muted_color), 0);
        }
        const counter_border = if (focused == self.counter) accent_color else c.color(border_color);
        c.lv_obj_set_style_border_color(self.minus, counter_border, 0);
        c.lv_obj_set_style_border_color(self.plus, counter_border, 0);
        const arrows = if (focused == self.chooser) accent_color else c.color(ui.muted_color);
        c.lv_obj_set_style_text_color(self.chooser_left, arrows, 0);
        c.lv_obj_set_style_text_color(self.chooser_right, arrows, 0);

        const typing = focused == self.name;
        c.lv_label_set_text(self.hint, if (typing) "type a name  ENTER next" else "F/X move  Z/C change  ENTER press");
        if (self.screen.shown()) c.cp0_app_set_text_input(@intFromBool(typing));
    }

    /// The accent color is whatever the chooser picked; every focus style uses it.
    fn applyAccent(self: *Widgets) void {
        const color = c.color(self.accent());
        c.lv_obj_set_style_border_color(self.name, color, c.state.focused);
        c.lv_obj_set_style_bg_color(self.name, color, c.part.cursor | c.state.focused);
        c.lv_obj_set_style_border_color(self.button, color, c.state.focused);
        c.lv_obj_set_style_bg_color(self.button, color, c.state.pressed);
        c.lv_obj_set_style_bg_color(self.volume, color, c.part.indicator);
        c.lv_obj_set_style_text_color(self.chooser, color, c.part.selected);
        c.lv_obj_set_style_bg_color(self.swatch, color, 0);
        c.lv_obj_set_style_bg_color(self.sound, color, c.part.indicator | c.state.checked);
        c.lv_obj_set_style_text_color(self.status, color, 0);
        self.refreshFocus();
    }

    fn focusCb(group: *c.Group) callconv(.c) void {
        const self: *Widgets = @ptrCast(@alignCast(c.lv_group_get_user_data(group) orelse return));
        self.refreshFocus();
    }

    fn buttonClickedCb(event: *c.Event) callconv(.c) void {
        const self = c.eventUserData(Widgets, event);
        const name = std.mem.trim(u8, std.mem.span(c.lv_textarea_get_text(self.name)), " \t");
        var text: [64]u8 = undefined;
        self.setStatus(std.fmt.bufPrint(&text, "Hello, {s}!", .{if (name.len == 0) "stranger" else name}) catch unreachable);
    }

    fn buttonReleaseCb(timer: *c.Timer) callconv(.c) void {
        const self = c.timerUserData(Widgets, timer);
        c.lv_obj_remove_state(self.button, c.state.pressed);
        self.release_timer = null; // a one-shot timer deletes itself
    }

    fn volumeChangedCb(event: *c.Event) callconv(.c) void {
        const self = c.eventUserData(Widgets, event);
        var number: [16]u8 = undefined;
        const value = std.fmt.bufPrint(&number, "{d}", .{c.lv_slider_get_value(self.volume)}) catch unreachable;
        c.setText(self.volume_value, value);
        var text: [32]u8 = undefined;
        self.setStatus(std.fmt.bufPrint(&text, "Volume {s}", .{value}) catch unreachable);
    }

    fn stepCount(self: *Widgets, step: i32) void {
        var text: [32]u8 = undefined;
        self.setCount(self.count + step, std.fmt.bufPrint(&text, "Count {d}", .{self.count + step}) catch unreachable);
    }

    fn minusClickedCb(event: *c.Event) callconv(.c) void {
        c.eventUserData(Widgets, event).stepCount(-1);
    }

    fn plusClickedCb(event: *c.Event) callconv(.c) void {
        c.eventUserData(Widgets, event).stepCount(1);
    }

    fn choiceChangedCb(event: *c.Event) callconv(.c) void {
        const self = c.eventUserData(Widgets, event);
        self.applyAccent();
        var text: [32]u8 = undefined;
        const choice = choices[c.lv_roller_get_selected(self.chooser)];
        self.setStatus(std.fmt.bufPrint(&text, "Color {s}", .{choice.name}) catch unreachable);
    }

    fn soundChangedCb(event: *c.Event) callconv(.c) void {
        const self = c.eventUserData(Widgets, event);
        const on_off = if (c.lv_obj_has_state(self.sound, c.state.checked)) "on" else "off";
        c.setText(self.sound_value, on_off);
        var text: [16]u8 = undefined;
        self.setStatus(std.fmt.bufPrint(&text, "Sound {s}", .{on_off}) catch unreachable);
    }

    /// The app ends by deleting the page. Before the widgets go, drop the group (whose
    /// focus callback would otherwise see them half-deleted) and the button timer.
    fn rootDeletedCb(event: *c.Event) callconv(.c) void {
        const self = c.eventUserData(Widgets, event);
        if (self.release_timer) |timer| c.lv_timer_delete(timer);
        self.release_timer = null;
        c.lv_group_delete(self.group);
    }

    fn makeName(self: *Widgets, y: i32) void {
        const name = c.lv_textarea_create(self.screen.root);
        self.name = name;
        c.lv_obj_remove_style_all(name);
        styleBox(name, field_color);
        c.lv_textarea_set_one_line(name, true);
        c.lv_textarea_set_placeholder_text(name, "your name");
        c.lv_textarea_set_max_length(name, max_name);
        c.setPadHor(name, 4, 0);
        c.lv_obj_set_pos(name, widget_left, y);
        c.lv_obj_set_size(name, widget_width, row_height);
        c.lv_obj_set_style_text_color(name, c.color(ui.muted_color), c.part.textarea_placeholder);
        // An empty focused field shows just the cursor: a solid block that does not blink.
        c.lv_obj_set_style_text_opa(name, c.opa_transp, c.part.textarea_placeholder | c.state.focused);
        c.lv_obj_set_style_bg_opa(name, c.opa_cover, c.part.cursor | c.state.focused);
        c.lv_obj_set_style_pad_right(name, 4, c.part.cursor);
        c.lv_obj_set_style_anim_duration(name, 0, c.part.cursor);
    }

    fn makeButton(self: *Widgets, y: i32) void {
        self.button = makeBoxButton(self.screen.root, "Say hello", widget_left, y, 120);
        c.lv_obj_set_style_text_color(self.button, c.color(ui.background_color), c.state.pressed);
        c.onEvent(self.button, .clicked, buttonClickedCb, self);
    }

    fn makeVolume(self: *Widgets, y: i32) void {
        const volume = c.lv_slider_create(self.screen.root);
        self.volume = volume;
        c.lv_obj_remove_style_all(volume);
        c.lv_obj_set_pos(volume, widget_left, y + 7);
        c.lv_obj_set_size(volume, slider_width, 4);
        c.lv_slider_set_range(volume, 0, 100);
        c.lv_slider_set_value(volume, 50, c.anim_off);
        c.lv_obj_set_style_bg_color(volume, c.color(border_color), 0);
        c.lv_obj_set_style_bg_opa(volume, c.opa_cover, 0);
        c.lv_obj_set_style_bg_opa(volume, c.opa_cover, c.part.indicator);
        // The knob is the 4 px track height grown by its padding: 6 x 14.
        c.lv_obj_set_style_bg_color(volume, c.color(ui.muted_color), c.part.knob);
        c.lv_obj_set_style_bg_color(volume, c.color(ui.text_color), c.part.knob | c.state.focused);
        c.lv_obj_set_style_bg_opa(volume, c.opa_cover, c.part.knob);
        c.setPadHor(volume, 1, c.part.knob);
        c.setPadVer(volume, 5, c.part.knob);
        c.onEvent(volume, .value_changed, volumeChangedCb, self);

        self.volume_value = ui.makeLabel(self.screen.root, "50", &c.lv_font_montserrat_14, ui.text_color);
        c.lv_obj_set_pos(self.volume_value, widget_left + slider_width + 12, y + 1);
    }

    fn makeCounter(self: *Widgets, y: i32) void {
        // One focusable container holding "-", the value and "+".
        self.counter = ui.makePanel(self.screen.root, widget_left, y, 108, row_height, ui.background_color, c.opa_transp);
        self.minus = makeBoxButton(self.counter, "-", 0, 0, 24);
        self.plus = makeBoxButton(self.counter, "+", 84, 0, 24);
        c.onEvent(self.minus, .clicked, minusClickedCb, self);
        c.onEvent(self.plus, .clicked, plusClickedCb, self);
        self.count_value = ui.makeLabel(self.counter, "0", &c.lv_font_montserrat_14, ui.text_color);
        c.lv_obj_set_width(self.count_value, 60);
        c.lv_obj_set_style_text_align(self.count_value, .center, 0);
        c.lv_obj_set_pos(self.count_value, 24, 1);
    }

    fn makeChooser(self: *Widgets, y: i32) void {
        const root = self.screen.root;
        self.chooser_left = ui.makeLabel(root, "<", &c.lv_font_montserrat_14, ui.muted_color);
        c.lv_obj_set_pos(self.chooser_left, widget_left, y + 1);
        const chooser = c.lv_roller_create(root);
        self.chooser = chooser;
        c.lv_obj_remove_style_all(chooser);
        c.lv_obj_set_style_text_font(chooser, &c.lv_font_montserrat_14, 0);
        c.lv_obj_set_style_text_font(chooser, &c.lv_font_montserrat_14, c.part.selected);
        c.lv_obj_set_style_text_align(chooser, .center, 0);
        c.lv_roller_set_options(chooser, choice_options, .normal);
        c.lv_roller_set_visible_row_count(chooser, 1);
        c.lv_roller_set_selected(chooser, defaultChoice(), c.anim_off);
        c.lv_obj_set_pos(chooser, widget_left + 12, y + 1);
        c.lv_obj_set_width(chooser, 56);
        c.onEvent(chooser, .value_changed, choiceChangedCb, self);
        self.chooser_right = ui.makeLabel(root, ">", &c.lv_font_montserrat_14, ui.muted_color);
        c.lv_obj_set_pos(self.chooser_right, widget_left + 72, y + 1);
        self.swatch = ui.makePanel(root, widget_left + 88, y + 2, 14, row_height - 4, ui.language_color, c.opa_cover);
    }

    fn makeSwitch(self: *Widgets, y: i32) void {
        const sound = c.lv_switch_create(self.screen.root);
        self.sound = sound;
        c.lv_obj_remove_style_all(sound);
        c.lv_obj_set_pos(sound, widget_left, y + 2);
        c.lv_obj_set_size(sound, 32, row_height - 4);
        c.lv_obj_set_style_bg_color(sound, c.color(border_color), 0);
        c.lv_obj_set_style_bg_opa(sound, c.opa_cover, 0);
        c.lv_obj_set_style_bg_opa(sound, c.opa_cover, c.part.indicator | c.state.checked);
        c.lv_obj_set_style_bg_color(sound, c.color(ui.text_color), c.part.knob);
        c.lv_obj_set_style_bg_opa(sound, c.opa_cover, c.part.knob);
        c.setPadAll(sound, -2, c.part.knob);
        c.lv_obj_set_style_outline_color(sound, c.color(ui.text_color), c.state.focused);
        c.lv_obj_set_style_outline_width(sound, 1, c.state.focused);
        c.lv_obj_set_style_outline_pad(sound, 2, c.state.focused);
        c.lv_obj_add_state(sound, c.state.checked);
        c.onEvent(sound, .value_changed, soundChangedCb, self);

        self.sound_value = ui.makeLabel(self.screen.root, "on", &c.lv_font_montserrat_14, ui.text_color);
        c.lv_obj_set_pos(self.sound_value, widget_left + 40, y + 1);
    }

    fn rowTop(row: Row) i32 {
        return rows_top + @as(i32, @backingInt(row)) * row_height;
    }

    fn makeRows(self: *Widgets) void {
        for (row_labels, &self.bars, &self.labels, 0..) |text, *bar, *label, index| {
            const y: i32 = rows_top + @as(i32, @intCast(index)) * row_height;
            bar.* = ui.makePanel(self.screen.root, 0, y, 3, row_height, ui.language_color, c.opa_cover);
            label.* = ui.makeLabel(self.screen.root, text, &c.lv_font_montserrat_14, ui.muted_color);
            c.lv_obj_set_pos(label.*, 8, y + 1);
        }
        self.makeName(rowTop(.name));
        self.makeButton(rowTop(.button));
        self.makeVolume(rowTop(.volume));
        self.makeCounter(rowTop(.count));
        self.makeChooser(rowTop(.color));
        self.makeSwitch(rowTop(.sound));
        self.widgets = .{ self.name, self.button, self.volume, self.counter, self.chooser, self.sound };
    }

    pub fn init(self: *Widgets, parent: *c.Obj) void {
        self.* = .{ .screen = .init(parent) };
        self.status = ui.makeLabel(self.screen.root, "Try every widget", &c.lv_font_montserrat_14, ui.language_color);
        c.lv_obj_set_pos(self.status, 8, 0);
        _ = ui.makeDemoKeys(self.screen.root);
        self.makeRows();
        self.hint = ui.makeHint(self.screen.root, "");

        self.group = c.lv_group_create();
        c.lv_group_set_wrap(self.group, true);
        for (self.widgets) |widget| c.lv_group_add_obj(self.group, widget);
        c.lv_group_focus_obj(self.name);
        c.lv_group_set_user_data(self.group, self);
        c.lv_group_set_focus_cb(self.group, focusCb);
        c.onEvent(self.screen.root, .delete, rootDeletedCb, self);
        self.applyAccent();
    }

    /// ENTER on the button: show it pressed for a moment and click it.
    fn pressButton(self: *Widgets) void {
        c.lv_obj_add_state(self.button, c.state.pressed);
        if (self.release_timer) |timer| c.lv_timer_delete(timer);
        const timer = c.lv_timer_create(buttonReleaseCb, press_ms, self);
        c.lv_timer_set_repeat_count(timer, 1);
        self.release_timer = timer;
        c.sendEvent(self.button, .clicked);
    }

    /// Z/C (or left/right): step the focused widget's value.
    fn change(self: *Widgets, step: i32) void {
        const focused = c.lv_group_get_focused(self.group);
        if (focused == self.volume) {
            const value = c.lv_slider_get_value(self.volume) + step * volume_step;
            c.lv_slider_set_value(self.volume, std.math.clamp(value, 0, 100), c.anim_off);
            c.sendEvent(self.volume, .value_changed);
        } else if (focused == self.counter) {
            c.sendEvent(if (step < 0) self.minus else self.plus, .clicked);
        } else if (focused == self.chooser) {
            const count: i32 = choices.len;
            const selected: i32 = @intCast(c.lv_roller_get_selected(self.chooser));
            c.lv_roller_set_selected(self.chooser, @intCast(@mod(selected + step, count)), c.anim_off);
            c.sendEvent(self.chooser, .value_changed);
        } else if (focused == self.sound) {
            c.lv_obj_set_state(self.sound, c.state.checked, !c.lv_obj_has_state(self.sound, c.state.checked));
            c.sendEvent(self.sound, .value_changed);
        }
    }

    /// ENTER or SPACE on the focused widget.
    fn activate(self: *Widgets) void {
        const focused = c.lv_group_get_focused(self.group);
        if (focused == self.button) {
            self.pressButton();
        } else if (focused == self.counter) {
            self.setCount(0, "Count reset");
        } else if (focused == self.chooser or focused == self.sound) {
            self.change(1);
        }
    }

    pub fn onShow(self: *Widgets) void {
        // Keys come only through the key callback while the form shows (see the top of this file).
        c.cp0_app_set_keypad_intercept(1);
        self.refreshFocus();
    }

    pub fn onHide(_: *Widgets) void {
        c.cp0_app_set_keypad_intercept(0);
        c.cp0_app_set_text_input(0);
    }

    pub fn handleKey(self: *Widgets, key: *const c.Key) Action {
        switch (key.code) {
            ui.keys.esc => return .home,
            ui.keys.tab => return .next,
            // Real arrow keys always move the focus, even out of the text field.
            ui.keys.up => {
                c.lv_group_focus_prev(self.group);
                return .stay;
            },
            ui.keys.down => {
                c.lv_group_focus_next(self.group);
                return .stay;
            },
            else => {},
        }
        if (c.lv_group_get_focused(self.group) == self.name) {
            // In the text field F/X/Z/C are letters; ENTER moves on.
            if (key.code == ui.keys.enter) {
                c.lv_group_focus_next(self.group);
            } else if (key.code == ui.keys.backspace) {
                c.lv_textarea_delete_char(self.name);
            } else if (ui.typedText(key) != null) {
                c.lv_textarea_add_text(self.name, key.text);
            }
            return .stay;
        }
        if (ui.direction(key.code)) |direction| switch (direction) {
            .up => c.lv_group_focus_prev(self.group),
            .down => c.lv_group_focus_next(self.group),
            .left => self.change(-1),
            .right => self.change(1),
        } else if (key.code == ui.keys.enter or key.code == ui.keys.space) {
            self.activate();
        }
        return .stay;
    }
};
