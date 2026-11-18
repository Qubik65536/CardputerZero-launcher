// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! zig build              desktop build (zig-out/bin/hello-cardputer): an SDL window, or the
//!                        fbsim / emulator screen when one of them starts it
//! zig build run          build and run it from this directory (images load from ./APPLaunch)
//! zig build device       aarch64 Linux binary for the CardputerZero (zig-out/device/hello-cardputer)
//! zig build test         unit tests (the calc language, the Motion readout); no runtime needed
//!
//! The app links against the LVGL runtime: LVGL 9.5, cp0_lvgl and its C API cp0_app.h,
//! built once per machine and target with
//!
//!     ../../scripts/lvgl-runtime/build.sh desktop
//!     ../../scripts/lvgl-runtime/build.sh device
//!
//! Each runtime build writes out/<desktop|device>/ldflags.txt: the arguments a C compiler
//! links a cp0_app program with, one per line. linkRuntime() turns them into Zig build
//! calls. If the app does not live in projects/<Name>/ of the launcher repository, point
//! at the runtime with -Dlvgl-runtime=/path/to/launcher/scripts/lvgl-runtime.

const std = @import("std");

const name = "hello-cardputer";

/// The two builds of the runtime: this computer, and the CardputerZero.
const Kind = enum { desktop, device };

/// The device runs Debian with glibc 2.41; the runtime's libraries use symbols that
/// older glibc versions lack (__isoc23_strtol and friends).
const device_query: std.Target.Query = .{
    .cpu_arch = .aarch64,
    .os_tag = .linux,
    .abi = .gnu,
    .glibc_version = .{ .major = 2, .minor = 41, .patch = 0 },
};

/// Libraries that are part of libc (Zig links libc itself) or of Zig's compiler_rt (libgcc).
const libc_parts = [_][]const u8{ "c", "m", "pthread", "dl", "rt", "gcc" };

fn exists(b: *std.Build, path: []const u8) bool {
    std.Io.Dir.cwd().access(b.graph.io, path, .{}) catch return false;
    return true;
}

/// For a path that does not exist (yet): redo the build configuration when it appears,
/// by watching the entries of its closest existing parent directory. (Zig 0.17.0 cannot
/// track a missing file directly: dependOnFileContents fails the configuration.)
fn dependOnCreation(b: *std.Build, path: []const u8) void {
    var parent = std.fs.path.dirname(path);
    while (parent) |dir| : (parent = std.fs.path.dirname(dir)) {
        if (exists(b, dir)) return b.dependOnDirectoryContents(b.graph.cwdRelativePath(dir));
    }
}

/// The contents of the file at `path`, or null if there is none. The build
/// configuration is redone when the file appears, changes or disappears.
fn readFile(b: *std.Build, path: []const u8) ?[]const u8 {
    if (!exists(b, path)) {
        dependOnCreation(b, path);
        return null;
    }
    b.dependOnFileContents(b.graph.cwdRelativePath(path));
    return std.Io.Dir.cwd().readFileAlloc(b.graph.io, path, b.graph.arena, .limited(1 << 20)) catch |err|
        std.debug.panic("cannot read {s}: {t}", .{ path, err });
}

/// The full path of `file_name` in the first of `dirs` that has it.
fn findFile(b: *std.Build, dirs: []const []const u8, file_name: []const u8) ?[]const u8 {
    for (dirs) |dir| {
        const path = b.pathJoin(&.{ dir, file_name });
        if (!exists(b, path)) {
            dependOnCreation(b, path);
            continue;
        }
        b.dependOnFileMetadata(b.graph.cwdRelativePath(path));
        return path;
    }
    return null;
}

/// Link a shared library given by file name (`-l:libdbus-1.so.3`), searching `dirs`.
fn linkFileFromDirs(b: *std.Build, module: *std.Build.Module, dirs: []const []const u8, file_name: []const u8) ?[]const u8 {
    const path = findFile(b, dirs, file_name) orelse
        return b.fmt("{s} is not in any of the runtime's library directories", .{file_name});
    module.addObjectFile(b.graph.cwdRelativePath(path));
    return null;
}

/// Directories a Linux system keeps its own libraries in, for the desktop build on Linux.
fn systemLibraryDirs(b: *std.Build, target: std.Target) []const []const u8 {
    const triple = b.fmt("{t}-linux-gnu", .{target.cpu.arch});
    return b.graph.arena.dupe([]const u8, &.{
        b.pathJoin(&.{ "/usr/lib", triple }),
        b.pathJoin(&.{ "/lib", triple }),
        "/usr/lib64",
        "/usr/lib",
    }) catch @panic("OOM");
}

/// Translate ldflags.txt into calls on `module`:
///   -L<dir>              addLibraryPath
///   -l<name>             linkSystemLibrary (static archives such as libcp0_lvgl.a, or
///                        shared libraries such as libSDL2 and libinput)
///   -l:<file>, *.so.N    addObjectFile: a shared library linked by its file name
///   -Wl,-framework,<X>   linkFramework (macOS)
///   -lc++ / -lstdc++     the C++ runtime the libraries were compiled against: on macOS
///                        Zig's libc++; on Linux the system's libstdc++ (and libgcc_s, its
///                        unwinder), since g++-compiled code needs GNU libstdc++
///   -lc -lm -lpthread -lgcc, --sysroot=, -B, -Wl,-rpath-link, -pthread: nothing to do,
///                        Zig brings its own libc, compiler_rt and search logic
/// Returns why linking cannot work, or null.
fn linkRuntime(b: *std.Build, module: *std.Build.Module, ldflags: []const u8) ?[]const u8 {
    const target = module.resolved_target.?.result;
    const arena = b.graph.arena;
    var dirs: std.ArrayList([]const u8) = .empty;
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    var libstdcxx = false;

    var lines = std.mem.tokenizeAny(u8, ldflags, "\r\n");
    while (lines.next()) |flag| {
        if (std.mem.startsWith(u8, flag, "-L")) {
            module.addLibraryPath(b.graph.cwdRelativePath(flag[2..]));
            dirs.append(arena, flag[2..]) catch @panic("OOM");
        }
    }

    lines.reset();
    while (lines.next()) |flag| {
        // Each library once: the C link line repeats some for the linker's sake.
        if ((seen.getOrPut(arena, flag) catch @panic("OOM")).found_existing) continue;
        if (std.mem.startsWith(u8, flag, "-L") or std.mem.startsWith(u8, flag, "--sysroot=") or
            std.mem.startsWith(u8, flag, "-B") or std.mem.startsWith(u8, flag, "-Wl,-rpath-link,") or
            std.mem.eql(u8, flag, "-pthread"))
        {
            continue;
        } else if (std.mem.startsWith(u8, flag, "-Wl,-framework,")) {
            module.linkFramework(flag["-Wl,-framework,".len..], .{});
        } else if (std.mem.startsWith(u8, flag, "-l:")) {
            if (linkFileFromDirs(b, module, dirs.items, flag[3..])) |problem| return problem;
        } else if (std.mem.eql(u8, flag, "-lc++") or std.mem.eql(u8, flag, "-lstdc++")) {
            if (target.os.tag.isDarwin()) {
                module.link_libcpp = true;
            } else {
                const search = std.mem.concat(arena, []const u8, &.{ dirs.items, systemLibraryDirs(b, target) }) catch @panic("OOM");
                if (linkFileFromDirs(b, module, search, "libstdc++.so.6")) |problem| return problem;
                libstdcxx = true;
            }
        } else if (std.mem.startsWith(u8, flag, "-l")) {
            const library = flag[2..];
            for (libc_parts) |part| {
                if (std.mem.eql(u8, library, part)) break;
            } else module.linkSystemLibrary(library, .{ .use_pkg_config = .no });
        } else if (std.fs.path.isAbsolute(flag) and (std.mem.endsWith(u8, flag, ".a") or std.mem.endsWith(u8, flag, ".so") or
            std.mem.indexOf(u8, flag, ".so.") != null))
        {
            module.addObjectFile(b.graph.cwdRelativePath(flag));
            if (std.mem.startsWith(u8, std.fs.path.basename(flag), "libstdc++")) libstdcxx = true;
        } else {
            return b.fmt("unexpected flag in ldflags.txt: {s}", .{flag});
        }
    }

    if (libstdcxx) {
        // libstdc++ unwinds exceptions with libgcc_s; gcc adds it by itself, Zig does not.
        const search = std.mem.concat(arena, []const u8, &.{ dirs.items, systemLibraryDirs(b, target) }) catch @panic("OOM");
        if (linkFileFromDirs(b, module, search, "libgcc_s.so.1")) |problem| return problem;
    }
    return null;
}

/// Where scripts/lvgl-runtime is: -Dlvgl-runtime, or two levels up as in projects/<Name>/.
fn runtimeDir(b: *std.Build) []const u8 {
    const root = b.root.toString(b.graph.arena) catch @panic("OOM");
    const relative = b.option([]const u8, "lvgl-runtime", "Path to the launcher's scripts/lvgl-runtime") orelse
        return b.pathResolve(&.{ root, "../../scripts/lvgl-runtime" });
    return b.pathResolve(&.{relative});
}

/// The app for `target`, linked against the `kind` build of the runtime. If that build
/// is missing (or unusable), building the app fails with a message saying what to do.
fn addApp(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    runtime: []const u8,
    kind: Kind,
) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    const ldflags_path = b.pathJoin(&.{ runtime, "out", @tagName(kind), "ldflags.txt" });
    const problem = if (readFile(b, ldflags_path)) |ldflags|
        linkRuntime(b, exe.root_module, ldflags)
    else
        b.fmt("the LVGL runtime for the {t} is not built ({s} is missing): run {s}/build.sh {t}", .{ kind, ldflags_path, runtime, kind });
    if (problem) |message| exe.step.dependOn(&b.addFail(message).step);
    return exe;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const runtime = runtimeDir(b);

    const exe = addApp(b, target, optimize, runtime, .desktop);
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    run.setCwd(b.path(".")); // cp0_lvgl loads images from ./APPLaunch/share/images
    run.addPassthruArgs();
    run.step.dependOn(b.getInstallStep());
    b.step("run", "Build and run the app on this computer").dependOn(&run.step);

    const device_exe = addApp(b, b.resolveTargetQuery(device_query), if (optimize == .debug) .safe else optimize, runtime, .device);
    const install_device = b.addInstallArtifact(device_exe, .{ .dest_dir = .{ .override = .{ .custom = "device" } } });
    b.step("device", "Build the CardputerZero (aarch64 Linux) binary").dependOn(&install_device.step);

    // The tests cover code that does not call LVGL, so they need no runtime.
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.step("test", "Run the unit tests").dependOn(&b.addRunArtifact(tests).step);
}
