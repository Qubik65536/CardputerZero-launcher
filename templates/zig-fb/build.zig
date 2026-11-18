// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! zig build              desktop build (zig-out/bin/hello-cardputer)
//! zig build sim          run it in the fbsim window (build scripts/fbsim first)
//! zig build device       static aarch64 Linux binary for the CardputerZero
//!                        (zig-out/device/hello-cardputer)
//! zig build test         unit tests (the calc language in src/calc.zig)

const std = @import("std");

const name = "hello-cardputer";

fn addApp(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    return b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const fbsim = b.option([]const u8, "fbsim", "Path to the fbsim simulator") orelse "../../scripts/fbsim/fbsim";

    const exe = addApp(b, target, optimize);
    b.installArtifact(exe);

    const sim = b.addSystemCommand(&.{ fbsim, "--" });
    sim.addArtifactArg(exe);
    b.step("sim", "Run in the desktop framebuffer simulator (fbsim)").dependOn(&sim.step);

    // Zig's standard library talks to Linux directly, so the device binary needs
    // no libc: it is fully static and independent of the device's glibc version.
    const device_target = b.resolveTargetQuery(.{ .cpu_arch = .aarch64, .os_tag = .linux });
    const device_exe = addApp(b, device_target, if (optimize == .debug) .safe else optimize);
    const install_device = b.addInstallArtifact(device_exe, .{ .dest_dir = .{ .override = .{ .custom = "device" } } });
    b.step("device", "Build the CardputerZero (aarch64 Linux) binary").dependOn(&install_device.step);

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/calc.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.step("test", "Run the unit tests").dependOn(&b.addRunArtifact(tests).step);
}
