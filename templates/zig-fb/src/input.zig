// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! Keyboard input as Linux evdev events.
//!
//! On the device this reads the built-in keyboard's evdev device. Under `fbsim`
//! it reads the FIFO named by CARDPUTER_INPUT, which carries the same 24-byte
//! `struct input_event` records. Reads are non-blocking: `poll()` returns null
//! when nothing is pending.
//!
//! Keys report Linux key codes. Letters, digits, ENTER, ESC, BACKSPACE, TAB and
//! SPACE are standard; the keyboard's symbol layer uses its own codes (see
//! docs/app-development/device-reference.md).

const std = @import("std");

const posix = std.posix;
const Io = std.Io;

/// Linux key codes (linux/input-event-codes.h) that apps commonly need.
pub const keys = struct {
    pub const esc: u16 = 1;
    pub const backspace: u16 = 14;
    pub const tab: u16 = 15;
    pub const leftshift: u16 = 42;
    pub const rightshift: u16 = 54;
    pub const digit_1: u16 = 2;
    pub const digit_2: u16 = 3;
    pub const digit_3: u16 = 4;
    pub const digit_4: u16 = 5;
    pub const enter: u16 = 28;
    pub const space: u16 = 57;
    pub const up: u16 = 103;
    pub const left: u16 = 105;
    pub const right: u16 = 106;
    pub const down: u16 = 108;
    pub const q: u16 = 16;
    pub const f: u16 = 33;
    pub const z: u16 = 44;
    pub const x: u16 = 45;
    pub const c: u16 = 46;
};

pub const KeyState = enum { released, pressed, repeated };

pub const KeyEvent = struct {
    code: u16,
    state: KeyState,

    /// True for a fresh press or an auto-repeat: what most UIs act on.
    pub fn isDown(self: KeyEvent) bool {
        return self.state != .released;
    }
};

pub const Direction = enum { up, down, left, right };

/// The CardputerZero keyboard has no arrow keys: like the launcher, treat
/// F/X/Z/C as up/down/left/right. Real arrow keys (desktop simulator, external
/// keyboards) work too.
pub fn direction(code: u16) ?Direction {
    return switch (code) {
        keys.up, keys.f => .up,
        keys.down, keys.x => .down,
        keys.left, keys.z => .left,
        keys.right, keys.c => .right,
        else => null,
    };
}

const ev_key: u16 = 1;
const input_event_size = 24; // struct input_event on 64-bit Linux

fn parseEvent(record: *const [input_event_size]u8) ?KeyEvent {
    const kind = std.mem.readInt(u16, record[16..18], .little);
    const code = std.mem.readInt(u16, record[18..20], .little);
    const value = std.mem.readInt(i32, record[20..24], .little);
    if (kind != ev_key) return null;
    return .{
        .code = code,
        .state = switch (value) {
            0 => .released,
            1 => .pressed,
            else => .repeated,
        },
    };
}

const DesktopRow = struct { first: u16, plain: []const u8, shifted: []const u8 };

/// US desktop keyboard rows: key code of the first key, unshifted and shifted characters.
const desktop_rows = [_]DesktopRow{
    .{ .first = 2, .plain = "1234567890-=", .shifted = "!@#$%^&*()_+" },
    .{ .first = 16, .plain = "qwertyuiop[]", .shifted = "QWERTYUIOP{}" },
    .{ .first = 30, .plain = "asdfghjkl;'`", .shifted = "ASDFGHJKL:\"~" },
    .{ .first = 43, .plain = "\\zxcvbnm,./", .shifted = "|ZXCVBNM<>?" },
};

const DeviceSymbol = struct { code: u16, char: u8 };

/// The CardputerZero's symbol layer (SYM + key) sends these codes; the table is the
/// launcher's default keymap (ext_components/cp0_lvgl/src/cp0/cp0_keyboard_keymap.c).
const device_symbols = [_]DeviceSymbol{
    .{ .code = 26, .char = '!' }, .{ .code = 27, .char = '@' }, .{ .code = 39, .char = '#' },  .{ .code = 40, .char = '$' },
    .{ .code = 41, .char = '%' }, .{ .code = 43, .char = '^' }, .{ .code = 51, .char = '&' },  .{ .code = 52, .char = '*' },
    .{ .code = 53, .char = '(' }, .{ .code = 94, .char = ')' }, .{ .code = 55, .char = '~' },  .{ .code = 69, .char = '`' },
    .{ .code = 70, .char = '_' }, .{ .code = 71, .char = '-' }, .{ .code = 72, .char = '+' },  .{ .code = 73, .char = '=' },
    .{ .code = 74, .char = '[' }, .{ .code = 75, .char = ']' }, .{ .code = 76, .char = '{' },  .{ .code = 77, .char = '}' },
    .{ .code = 79, .char = ';' }, .{ .code = 80, .char = ':' }, .{ .code = 81, .char = '\'' }, .{ .code = 82, .char = '"' },
    .{ .code = 83, .char = '<' }, .{ .code = 85, .char = '>' }, .{ .code = 86, .char = '\\' }, .{ .code = 89, .char = '|' },
    .{ .code = 90, .char = ',' }, .{ .code = 91, .char = '.' }, .{ .code = 92, .char = '/' },  .{ .code = 93, .char = '?' },
};

fn desktopChar(code: u16, shift: bool) ?u8 {
    if (code == keys.space) return ' ';
    for (desktop_rows) |row| {
        if (code < row.first) continue;
        const characters = if (shift) row.shifted else row.plain;
        const index = code - row.first;
        if (index < characters.len) return characters[index];
    }
    return null;
}

fn deviceChar(code: u16, shift: bool) ?u8 {
    for (device_symbols) |symbol| if (symbol.code == code) return symbol.char;
    // Letters, digits and space are where a PC keyboard has them; Shift makes capitals.
    const char = desktopChar(code, false) orelse return null;
    if (std.ascii.isAlphabetic(char)) return if (shift) std.ascii.toUpper(char) else char;
    return if (std.ascii.isDigit(char) or char == ' ') char else null;
}

/// Which characters keys type: the CardputerZero's own keyboard, or a US desktop
/// keyboard (fbsim and the emulator, which set CARDPUTER_INPUT).
pub const Layout = enum { device, desktop };

/// Turns key events into typed characters, keeping track of Shift.
pub const Typist = struct {
    layout: Layout,
    shift: bool = false,

    pub fn init(env: *const std.process.Environ.Map) Typist {
        return .{ .layout = if (env.get("CARDPUTER_INPUT") != null) .desktop else .device };
    }

    /// The character a key press types, if any. Feed it every event, releases
    /// included, so it sees Shift go up and down.
    pub fn charFor(self: *Typist, event: KeyEvent) ?u8 {
        if (event.code == keys.leftshift or event.code == keys.rightshift) {
            self.shift = event.isDown();
            return null;
        }
        if (!event.isDown()) return null;
        return switch (self.layout) {
            .device => deviceChar(event.code, self.shift),
            .desktop => desktopChar(event.code, self.shift),
        };
    }
};

/// The built-in keyboard's event device. APPLaunch exports its path to the apps
/// it starts; the fixed by-path name is the same device when run another way.
fn devicePath(env: *const std.process.Environ.Map) []const u8 {
    for ([_][]const u8{ "CARDPUTER_INPUT", "LV_LINUX_KEYBOARD_DEVICE", "APPLAUNCH_LINUX_KEYBOARD_DEVICE" }) |name| {
        if (env.get(name)) |path| if (path.len > 0) return path;
    }
    return "/dev/input/by-path/platform-3f804000.i2c-event";
}

pub const Keyboard = struct {
    fd: posix.fd_t,
    pending: [input_event_size]u8 = undefined,
    pending_len: usize = 0,

    pub fn open(env: *const std.process.Environ.Map) !Keyboard {
        const fd = try posix.openat(posix.AT.FDCWD, devicePath(env), .{ .ACCMODE = .RDONLY, .NONBLOCK = true }, 0);
        return .{ .fd = fd };
    }

    pub fn close(self: *Keyboard, io: Io) void {
        (Io.File{ .handle = self.fd, .flags = .{ .nonblocking = true } }).close(io);
    }

    /// The next pending key event, if any. Never blocks.
    pub fn poll(self: *Keyboard) !?KeyEvent {
        while (true) {
            const got = posix.read(self.fd, self.pending[self.pending_len..]) catch |err| switch (err) {
                error.WouldBlock => return null,
                else => return err,
            };
            if (got == 0) return null; // writer closed (simulator exited)
            self.pending_len += got;
            if (self.pending_len < input_event_size) continue;
            self.pending_len = 0;
            if (parseEvent(&self.pending)) |event| return event;
        }
    }
};
