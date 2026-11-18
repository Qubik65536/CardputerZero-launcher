<!-- SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
     SPDX-License-Identifier: MIT -->
# Terminal apps (any language)

Any program that reads stdin and writes stdout can be a CardputerZero app:
Python, Go, Rust, shell, C, OCaml, a TUI... With `Terminal=true` in its
`.desktop` entry, the launcher runs it inside its built-in terminal.

```ini
[Desktop Entry]
Name=Todo
Exec=/usr/share/APPLaunch/bin/todo
Icon=share/images/todo_100.png
Terminal=true
Type=Application
```

Package it like any other app: `scripts/package_app.py` accepts either an
aarch64 binary or an executable script with a `#!` line (for example
`#!/usr/bin/env python3`) as the manifest's `"binary"`.

## The terminal

Facts from `projects/APPLaunch/main/ui/page_app/ui_app_st*.cpp` and
`ext_components/cp0_lvgl/src/cp0_pty_posix.inc`:

| | |
| --- | --- |
| Size | **45 columns x 10 rows** (7x15 px cells, JetBrains Mono 12 px). Query it with `stty size`/`ioctl(TIOCGWINSZ)` rather than hard-coding |
| `TERM` | `vt100` for `.desktop` apps |
| Colors | 16-color palette: SGR 30-37/40-47/90-97/100-107; 256-color and truecolor codes are accepted and mapped to the nearest of the 16. Bold brightens, reverse and hidden work; underline, dim and blink are ignored |
| Cursor/screen | Cursor movement, erase, insert/delete, scroll regions, save/restore, show/hide cursor, application cursor keys. `?1049` clears the screen but there is no separate alternate screen |
| Line drawing | DEC line-drawing charsets are not supported: use plain ASCII or Unicode box characters |
| Scrollback | 200 lines; Shift + PgUp/PgDn |

## Keys your program receives

| Key | Bytes |
| --- | --- |
| Letters, digits, symbols | The character (UTF-8), including Ctrl combinations |
| ENTER | `\r` |
| BACKSPACE | `0x7f` |
| ESC | `\x1b` (holding ESC also auto-repeats it) |
| Arrows | `\e[A`..`\e[D` (`\eOA`..`\eOD` in application cursor mode) when an arrow key is sent; the built-in keyboard has no dedicated arrow keys, so also accept letters for navigation (e.g. F/X/Z/C like the launcher, or hjkl) |
| Home / End / Del / PgUp / PgDn | `\e[H` `\e[F` `\e[3~` `\e[5~` `\e[6~` |
| F1-F4, F5-F12 | `\eOP`..`\eOS`, `\e[15~`..`\e[24~` |

The terminal keeps a few keys for itself: **F6** toggles an 80x24 "big" view
and restarts the program, so don't rely on it; in the big view F4/F5/F7/F8
pan. Fn+H shows a help overlay.

## Launching and exiting

- `Exec` is split on spaces and run directly (no shell, no quotes): `Exec=/usr/share/APPLaunch/bin/todo --compact` works; quoting or pipes do not. Need a shell? Use a wrapper script.
- The program starts in `/usr/share/APPLaunch` as user `pi`.
- When it exits, the terminal shows `-- Press any key to exit --` and returns to the home screen on the next key. With `Sysplause=false` the key that ended your program is not swallowed first.
- Holding ESC for 3 seconds always returns home (the program is killed).

## Tips

- Design for 45x10: short lines, one screen at a time, no wide tables.
- Detect the size at runtime; the big view and future firmware may differ.
- Python: `python3` is installed on the device. Use `#!/usr/bin/env python3` in your script, or `Exec=/usr/bin/python3 /usr/share/APPLaunch/bin/todo.py`. (A bare `Exec=python3` clashes with the built-in Python app and is skipped.)
- Curses works with `TERM=vt100`; test locally in an 45x10 terminal window (`resize -s 10 45` or set your terminal's size).
