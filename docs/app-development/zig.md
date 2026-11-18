<!-- SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
     SPDX-License-Identifier: MIT -->
# Zig apps

The `zig-fb` template is a Zig **0.17** program that draws into the
framebuffer and reads the keyboard. Read [framebuffer apps](framebuffer-apps.md)
first for the shared model; this page covers the Zig specifics.

## Create, run, ship

```bash
python3 scripts/new_app.py zig-fb "Pixel Pet"        # -> projects/PixelPet/
cd projects/PixelPet

zig build sim                                        # desktop, in fbsim (build scripts/fbsim first)
zig build device                                     # zig-out/device/pixel-pet: static aarch64 binary
python3 ../../scripts/package_app.py .               # packages/pixel-pet_0.1.0_arm64.deb
```

`zig build device` needs no cross toolchain, sysroot or Docker. The binary
does not link libc (Zig's standard library talks to the Linux kernel
directly), so it is fully static and runs regardless of the device's glibc.
If the app is not inside the launcher repository, point `sim` at fbsim:
`zig build sim -Dfbsim=/path/to/launcher/scripts/fbsim/fbsim`.

**Zig version:** the template targets 0.17 (`build.zig.zon` →
`minimum_zig_version`). Zig's standard library changes between releases, I/O
especially; on a newer Zig, expect to adjust `display.zig` (`std.Io` file
calls) and `input.zig` (`std.posix`).

## Project tour

| File | Contents |
| --- | --- |
| `src/main.zig` | `App` (your state), `handleKey`, `draw`, and `main(init: std.process.Init)` with the loop |
| `src/display.zig` | `Display.open(io, env)`, `clear`, `fillRect`, `drawText`, `Display.textWidth`, `present`, `close`; `rgb(r, g, b)`, `black`, `white` |
| `src/input.zig` | `Keyboard.open(env)`, `poll() !?KeyEvent`, `close(io)`; `KeyEvent{ code, state }`, `isDown()`; `keys.*`; `direction(code) ?Direction` |
| `src/font.zig` | The 8x8 glyph table |
| `build.zig` | `zig build`, `zig build sim`, `zig build device` |

`Display` holds about 220 KB of buffers, so `main.zig` keeps it in a global
(`var screen: Display = undefined;`) rather than on the stack. `main` receives
`init.io` (the `std.Io` implementation) and `init.environ_map` (environment
variables), which the modules use.

## Common tasks

**A new screen or mode.** Add `screen: enum { menu, game, game_over }` to
`App`, and `switch` on it in `handleKey` and `draw`.

**Timed updates.** Read a clock each frame: `const now = std.Io.Clock.awake.now(io);`
and pass the difference to an `update` function; redraw every frame.

**Images.** Convert with `scripts/png_to_rgb565.py art/player.png src/player.rgb565 --alpha`
(keep the file under `src/` so `@embedFile` can reach it), then add to `Display`:

```zig
/// Draw an image made by scripts/png_to_rgb565.py (with or without --alpha).
pub fn drawImage(self: *Display, x: i32, y: i32, image: []const u8) void {
    const width: usize = std.mem.readInt(u16, image[0..2], .little);
    const height: usize = std.mem.readInt(u16, image[2..4], .little);
    const pixels = image[4 .. 4 + width * height * 2];
    const has_alpha = image.len >= 4 + width * height * 3;
    for (0..height) |row| for (0..width) |column| {
        const index = row * width + column;
        if (has_alpha and image[4 + width * height * 2 + index] < 128) continue;
        const color = std.mem.readInt(u16, pixels[index * 2 ..][0..2], .little);
        self.fillRect(x + @as(i32, @intCast(column)), y + @as(i32, @intCast(row)), 1, 1, color);
    };
}
```

Use it with `screen.drawImage(10, 30, @embedFile("player.rgb565"));`.

**Saving data.** `init.environ_map.get("HOME")` gives `/home/pi`; use
`std.Io.Dir` to create `~/.local/share/<app>/` and write files.

**C libraries.** Zig compiles and links C directly (`exe.root_module.addCSourceFile`,
`linkSystemLibrary`). Linking a device library (e.g. libpulse) means linking
glibc too: target `aarch64-linux-gnu.2.36` and provide the device sysroot (the
SCons projects download one to `SDK/github_source/static_lib_v0.0.7`).

## Testing

```bash
zig build test                                     # add `test` blocks + a test step as you grow
zig build && python3 ../../scripts/fbsim/headless.py \
    --keys "c c enter esc" --png /tmp/shot.png --expect-exit 0 -- ./zig-out/bin/pixel-pet
```
