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
