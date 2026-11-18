#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
# SPDX-License-Identifier: MIT
"""Install the desktop build of an app into the CardputerZero emulator's launcher.

    python3 scripts/emulator_install.py projects/PixelPet
    projects/CardputerZero-Emulator/build/cardputer-zero-emu     # open it from the home screen
    python3 scripts/emulator_install.py projects/PixelPet --remove

This is the emulator's version of installing the .deb: the launcher running in
the emulator lists the app, opens it when you press ENTER on its card, shows it
on the emulated screen and returns home when it exits (or after holding ESC for
3 s). It reads <app>/cardputer-app.json:

    "desktop_binary": "target/debug/pixel-pet"     # the build for this computer

(or pass --binary) and copies

    <resources>/applications/<id>.desktop  ->  <emulator>/applications/<id>.desktop
                                               with Exec pointing at the desktop binary
    <resources>/share/...                   ->  <emulator>/APPLaunch/share/...

The launcher rescans applications/ every 3 s, so a running emulator picks the
app up too. Rebuild the app and it runs the new build next time; no reinstall
needed unless the .desktop file or the icons change.
"""

import argparse
import importlib.util
import platform
import shutil
import sys
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
REPO_ROOT = SCRIPTS.parent
DEFAULT_EMULATOR = REPO_ROOT / "projects" / "CardputerZero-Emulator" / "build"
EMULATOR_BINARY = "cardputer-zero-emu"
ELF_MACHINES = {"x86_64": 62, "amd64": 62, "aarch64": 183, "arm64": 183}
MACHO_MAGICS = (b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe", b"\xca\xfe\xba\xbe")


def load_package_app():
    """package_app.py holds the manifest and .desktop checks; reuse them."""
    spec = importlib.util.spec_from_file_location("package_app", SCRIPTS / "package_app.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def fail(message):
    sys.exit(f"emulator_install: {message}")


def desktop_build_hint(app_dir):
    if (app_dir / "Cargo.toml").exists():
        return "cargo build   (then desktop_binary: target/debug/<id>)"
    if (app_dir / "build.zig").exists():
        return "zig build     (then desktop_binary: zig-out/bin/<id>)"
    if (app_dir / "dune-project").exists():
        return "dune build    (then desktop_binary: _build/default/src/main.exe)"
    if (app_dir / "SConstruct").exists():
        return "scons distclean && scons   (the desktop profile is the default; binary in dist/)"
    return "build it for this computer"


def check_host_binary(binary, app_dir):
    header = binary.read_bytes()[:20]
    if header[:2] == b"#!":
        return
    system = platform.system()
    if header[:4] == b"\x7fELF":
        machine = int.from_bytes(header[18:20], "little")
        host_machine = ELF_MACHINES.get(platform.machine().lower())
        if system == "Linux" and machine == host_machine:
            return
        fail(f"{binary} is a Linux build for another CPU (ELF machine {machine}), probably "
             f"the device build. Build for this computer: {desktop_build_hint(app_dir)}")
    if header[:4] in MACHO_MAGICS and system == "Darwin":
        return
    fail(f"{binary} does not run on this computer. Build it with: {desktop_build_hint(app_dir)}")


def install_desktop_entry(source, target, binary, package_app):
    lines = []
    for line in source.read_text(encoding="utf-8").splitlines():
        if line.strip().startswith("Exec="):
            arguments = line.split("=", 1)[1].strip().split(" ")[1:]
            line = "Exec=" + " ".join([str(binary), *arguments])
        lines.append(line)
    target.write_text("\n".join(lines) + "\n", encoding="utf-8")
    exec_line = package_app.parse_desktop(target).get("Exec", "")
    if package_app.UNSAFE_EXEC_CHARACTERS & set(exec_line):
        fail(f"the path {binary} contains characters the launcher rejects in Exec")


def record_path(emulator, app_id):
    return emulator / "emulator-installed" / f"{app_id}.txt"


def remove(emulator, app_id):
    record = record_path(emulator, app_id)
    if not record.exists():
        fail(f"{app_id} is not installed in {emulator}")
    for name in record.read_text(encoding="utf-8").splitlines():
        (emulator / name).unlink(missing_ok=True)
    record.unlink()
    print(f"removed {app_id} from {emulator}")


def install(app_dir, emulator, manifest, binary, package_app):
    app_id = manifest["id"]
    resources = app_dir / manifest.get("resources", "APPLaunch")
    desktop = resources / "applications" / f"{app_id}.desktop"
    if not desktop.exists():
        fail(f"{desktop} not found: every app needs a .desktop entry")
    package_app.check_desktop(desktop, app_id, resources)  # same rules as the device

    installed = []
    target = emulator / "applications" / f"{app_id}.desktop"
    target.parent.mkdir(parents=True, exist_ok=True)
    install_desktop_entry(desktop, target, binary, package_app)
    installed.append(target.relative_to(emulator).as_posix())

    share = resources / "share"
    for source in sorted(share.rglob("*")) if share.exists() else []:
        if source.is_file() and source.name != ".DS_Store":
            destination = emulator / "APPLaunch" / "share" / source.relative_to(share)
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)
            installed.append(destination.relative_to(emulator).as_posix())

    record = record_path(emulator, app_id)
    record.parent.mkdir(parents=True, exist_ok=True)
    record.write_text("\n".join(installed) + "\n", encoding="utf-8")
    print(f"installed {manifest['name']} ({app_id}) into {emulator}")
    print(f"  Exec={binary}")
    print(f"run: {emulator / EMULATOR_BINARY}   (the card appears within ~3 s)")


def parse_args(argv):
    parser = argparse.ArgumentParser(
        description="Install an app's desktop build into the CardputerZero emulator's launcher.")
    parser.add_argument("app", type=Path, help="app directory (with cardputer-app.json)")
    parser.add_argument("--binary", type=Path, help="desktop build (default: desktop_binary)")
    parser.add_argument("--emulator", type=Path, default=DEFAULT_EMULATOR,
                        help="emulator build directory (default: %(default)s)")
    parser.add_argument("--remove", action="store_true", help="uninstall the app instead")
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    package_app = load_package_app()
    app_dir = args.app.resolve()
    manifest = package_app.load_manifest(app_dir)
    emulator = args.emulator.resolve()
    if not (emulator / EMULATOR_BINARY).exists():
        fail(f"no {EMULATOR_BINARY} in {emulator}. Build the emulator first:\n"
             "  cd projects/CardputerZero-Emulator && cmake -S . -B build && cmake --build build -j8")
    if args.remove:
        remove(emulator, manifest["id"])
        return

    binary = args.binary or (app_dir / manifest["desktop_binary"]
                             if manifest.get("desktop_binary") else None)
    if binary is None:
        fail('add "desktop_binary" to cardputer-app.json or pass --binary')
    binary = binary.resolve()
    if not binary.is_file():
        fail(f"{binary} not found. Build it first: {desktop_build_hint(app_dir)}")
    check_host_binary(binary, app_dir)
    install(app_dir, emulator, manifest, binary, package_app)


if __name__ == "__main__":
    main()
