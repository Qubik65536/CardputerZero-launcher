<!-- SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
     SPDX-License-Identifier: MIT -->
# Packaging and deploying

## 1. Describe the app: `cardputer-app.json`

Every template has one:

```json
{
  "id": "pixel-pet",
  "name": "Pixel Pet",
  "version": "0.1.0",
  "description": "A tiny virtual pet.",
  "maintainer": "Your Name <you@example.com>",
  "binary": "target/aarch64-unknown-linux-gnu/release/pixel-pet",
  "depends": ["libpulse0"]
}
```

| Field | Meaning |
| --- | --- |
| `id` | Debian package name and installed executable name (lowercase, digits, `-`) |
| `name` | Shown on the home screen (also set in the `.desktop` file) |
| `version` | Starts with a digit; bump it for every release so `dpkg` upgrades |
| `binary` | Path (relative to the app) of the device build: an aarch64 binary or a `#!` script |
| `resources` | Optional, default `APPLaunch`: the folder with `applications/` and `share/` |
| `depends` | Optional Debian packages your app needs beyond the launcher itself |

## 2. Build the package

```bash
python3 scripts/package_app.py projects/PixelPet
# -> projects/PixelPet/packages/pixel-pet_0.1.0_arm64.deb
```

It installs:

```
/usr/share/APPLaunch/bin/pixel-pet
/usr/share/APPLaunch/applications/pixel-pet.desktop
/usr/share/APPLaunch/share/...            everything under your APPLaunch/share/ (icons, fonts, data)
```

and refuses to build a package the launcher would ignore: a binary that is not
aarch64, an `Exec` that does not point at `/usr/share/APPLaunch/bin/<id>`
or contains shell characters, `Type` other than `Application`, and a missing or
non-PNG icon. It runs anywhere Python 3 runs; `dpkg-deb` is not needed.

## 3. Install on the device

Over the network (SSH, user `pi`):

```bash
scp projects/PixelPet/packages/pixel-pet_0.1.0_arm64.deb pi@<device-ip>:
ssh pi@<device-ip> 'sudo dpkg -i pixel-pet_0.1.0_arm64.deb'
```

Over USB (enable ADB in *Settings > Developer*, see `docs/adb-debug-guide.md`;
`adb shell` is a root shell):

```bash
adb push projects/PixelPet/packages/pixel-pet_0.1.0_arm64.deb /tmp/
adb shell dpkg -i /tmp/pixel-pet_0.1.0_arm64.deb
```

The launcher notices the new `.desktop` file within about 3 seconds and adds the
app to the home screen. To remove it: `sudo dpkg -r pixel-pet`.

### Faster iteration while developing

Reinstalling the package is quick, but copying just the binary is quicker:

```bash
scp <device binary> pi@<device-ip>:/tmp/pixel-pet
ssh pi@<device-ip> 'sudo install -m 755 /tmp/pixel-pet /usr/share/APPLaunch/bin/pixel-pet'
```

Then start the app from the home screen. To see its output live:
`ssh pi@<device-ip> journalctl --user -u APPLaunch.service -f`.
Framebuffer apps can also be run straight from SSH after stopping the launcher
([details](framebuffer-apps.md#running-on-the-device)).

SCons projects can automate upload and install with `scons push`: fill in the
`[ssh]` section of a `setup.ini` next to `SConstruct` (host, user, password or
key, `remote_file_path`, and an `after_cmd` that installs and restarts things);
`projects/APPLaunch/setup.ini` is an example.

## 4. Publish to the App Store

The on-device **Store** installs `.deb` packages listed in the public registry
(`https://cardputerzero.github.io/generated/registry.json`); only reviewed
(approved) entries are installable. Submissions go through the developer portal
at `https://dev.cardputer.cc/#/upload`. `projects/Calculator/PUBLISH.md` walks
through a real submission, and `projects/Calculator/app-builder.json` shows the
store metadata (summary, categories, license, source repository, icon,
screenshots, permissions).

Before submitting, check:

- the package installs and starts on a device, and ESC returns to the home screen;
- the icon is a 100x100 PNG and the name fits under the icon;
- UI text is 12 px or larger;
- screenshots: `scripts/fbsim/headless.py --png` for framebuffer apps; for LVGL apps, capture the simulator window (the launcher's screenshot hotkey is paused while an app runs).

## Manual packages

For layouts `package_app.py` doesn't cover (system services, files outside
`/usr/share/APPLaunch`, maintainer scripts), build the `.deb` yourself with
`dpkg-deb --build` and the same layout; `docs/APPLaunch-App-打包指南.md`
(Chinese) and `docs/APPLaunch-App-packaging-guide-ja.md` (Japanese) describe
it. Note that in those guides the long-press key is ESC held for 3 s (not Home), and a
`Type` other than `Application` is rejected.
