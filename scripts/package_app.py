#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
# SPDX-License-Identifier: MIT
"""Package a CardputerZero app as an arm64 .deb that APPLaunch picks up.

    python3 scripts/package_app.py projects/WeatherStation
    python3 scripts/package_app.py . --binary path/to/aarch64-binary --out dist/

Reads <app>/cardputer-app.json:

    {
      "id": "weather-station",            # package + executable name
      "name": "Weather Station",          # shown on the home screen
      "version": "0.1.0",
      "description": "Local weather on the CardputerZero",
      "maintainer": "You <you@example.com>",
      "binary": "target/aarch64-unknown-linux-gnu/release/weather-station",
      "resources": "APPLaunch",           # optional, default "APPLaunch"
      "depends": ["libc6"]                # optional extra Debian dependencies
    }

and lays the package out the way APPLaunch expects:

    /usr/share/APPLaunch/bin/<id>                       the binary
    /usr/share/APPLaunch/applications/<id>.desktop      from <resources>/applications/
    /usr/share/APPLaunch/share/...                      from <resources>/share/ (icons, fonts, ...)

Before writing anything it checks the problems that make the launcher silently
skip an app: a non-aarch64 binary, a .desktop whose Exec is not the installed
binary or contains shell metacharacters, Type other than Application, and an
Icon that is missing or not a PNG. Pure Python: no dpkg-deb needed.
"""

import argparse
import io
import json
import re
import sys
import tarfile
import time
from pathlib import Path

INSTALL_ROOT = "usr/share/APPLaunch"
UNSAFE_EXEC_CHARACTERS = set("|&;<>`$\\\n\r")
ELF_MACHINE_AARCH64 = 183


def fail(message):
    sys.exit(f"package_app: {message}")


def load_manifest(app_dir):
    path = app_dir / "cardputer-app.json"
    if not path.exists():
        fail(f"{path} not found")
    manifest = json.loads(path.read_text(encoding="utf-8"))
    for key in ("id", "name", "version", "binary"):
        if not manifest.get(key):
            fail(f"{path}: missing '{key}'")
    if not re.fullmatch(r"[a-z0-9][a-z0-9.+-]+", manifest["id"]):
        fail(f"id '{manifest['id']}' must be a Debian package name (lowercase letters, digits, - . +)")
    if not re.fullmatch(r"[0-9][A-Za-z0-9.+~-]*", manifest["version"]):
        fail(f"version '{manifest['version']}' must start with a digit, e.g. 0.1.0")
    return manifest


def check_aarch64_elf(binary):
    header = binary.read_bytes()[:20]
    if header[:4] != b"\x7fELF":
        fail(f"{binary} is not an ELF executable (build for the device first)")
    machine = int.from_bytes(header[18:20], "little")
    if machine != ELF_MACHINE_AARCH64:
        fail(f"{binary} is not an aarch64 binary (ELF machine {machine}); use the device/cross build")


def parse_desktop(path):
    entries, in_section = {}, False
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line[0] in "#;":
            continue
        if line.startswith("["):
            in_section = line == "[Desktop Entry]"
            continue
        if in_section and "=" in line:
            key, value = line.split("=", 1)
            entries[key.strip()] = value.strip()
    return entries


def check_desktop(path, app_id, resources):
    entry = parse_desktop(path)
    expected_exec = f"/{INSTALL_ROOT}/bin/{app_id}"
    exec_line = entry.get("Exec", "")
    if not entry.get("Name"):
        fail(f"{path}: Name= is required")
    if entry.get("Type", "Application") != "Application":
        fail(f"{path}: Type must be Application (the launcher skips anything else)")
    if UNSAFE_EXEC_CHARACTERS & set(exec_line):
        fail(f"{path}: Exec contains shell metacharacters the launcher rejects: {exec_line!r}")
    if exec_line.split(" ")[0] != expected_exec:
        fail(f"{path}: Exec should start with {expected_exec} (got {exec_line!r})")
    icon = entry.get("Icon", "")
    if icon:
        if icon.startswith("/") and not icon.startswith(f"/{INSTALL_ROOT}/"):
            fail(f"{path}: Icon must live under /{INSTALL_ROOT}/ (use share/images/<file>.png)")
        relative = re.sub(rf"^/?({INSTALL_ROOT}/|APPLaunch/)", "", icon)
        if "/" not in relative:
            relative = f"share/images/{relative}"
        icon_file = resources / relative
        if not icon_file.exists():
            fail(f"{path}: Icon {icon!r} not found at {icon_file}")
        if icon_file.read_bytes()[:8] != b"\x89PNG\r\n\x1a\n":
            fail(f"{icon_file}: icons must be PNG (100x100 RGBA recommended)")


def collect_files(app_dir, manifest):
    """Map install path (relative to /) -> (source bytes, mode)."""
    app_id = manifest["id"]
    binary = (app_dir / manifest["binary"]).resolve()
    if not binary.exists():
        fail(f"binary {binary} not found (build for the device first)")
    check_aarch64_elf(binary)
    files = {f"{INSTALL_ROOT}/bin/{app_id}": (binary.read_bytes(), 0o755)}

    resources = app_dir / manifest.get("resources", "APPLaunch")
    desktop = resources / "applications" / f"{app_id}.desktop"
    if not desktop.exists():
        fail(f"{desktop} not found: every app needs a .desktop entry")
    check_desktop(desktop, app_id, resources)
    for source in sorted(resources.rglob("*")):
        if source.is_file() and source.name != ".DS_Store":
            relative = source.relative_to(resources).as_posix()
            if relative.startswith(("applications/", "share/")):
                files[f"{INSTALL_ROOT}/{relative}"] = (source.read_bytes(), 0o644)
    return files


def control_text(manifest, installed_kib):
    depends = ", ".join(["applaunch"] + list(manifest.get("depends", [])))
    description = manifest.get("description") or manifest["name"]
    return (
        f"Package: {manifest['id']}\n"
        f"Version: {manifest['version']}\n"
        "Architecture: arm64\n"
        f"Maintainer: {manifest.get('maintainer', 'Unknown <unknown@example.com>')}\n"
        f"Installed-Size: {installed_kib}\n"
        f"Depends: {depends}\n"
        "Section: misc\n"
        "Priority: optional\n"
        f"Description: {manifest['name']} for CardputerZero\n"
        f" {description}\n"
    )


def tar_gz(members):
    """members: path -> (bytes, mode). Directories are added implicitly, owned by root."""
    buffer = io.BytesIO()
    now = int(time.time())
    with tarfile.open(fileobj=buffer, mode="w:gz", format=tarfile.GNU_FORMAT) as archive:
        directories = sorted({str(Path(path).parents[index]) for path in members
                              for index in range(len(Path(path).parents) - 1)})
        for directory in directories:
            info = tarfile.TarInfo(f"./{directory}")
            info.type, info.mode, info.mtime = tarfile.DIRTYPE, 0o755, now
            archive.addfile(info)
        for path, (data, mode) in sorted(members.items()):
            info = tarfile.TarInfo(f"./{path}")
            info.size, info.mode, info.mtime = len(data), mode, now
            archive.addfile(info, io.BytesIO(data))
    return buffer.getvalue()


def ar_archive(members):
    """Minimal System V ar archive, as used by .deb files."""
    out = bytearray(b"!<arch>\n")
    for name, data in members:
        header = f"{name:<16}{int(time.time()):<12}{0:<6}{0:<6}{0o100644:<8o}{len(data):<10}`\n"
        out += header.encode("ascii") + data + (b"\n" if len(data) % 2 else b"")
    return bytes(out)


def parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("app_dir", type=Path, help="directory containing cardputer-app.json")
    parser.add_argument("--binary", type=Path, help="override the manifest's binary path")
    parser.add_argument("--out", type=Path, help="output directory (default: <app>/packages)")
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    app_dir = args.app_dir.resolve()
    manifest = load_manifest(app_dir)
    if args.binary:
        manifest["binary"] = str(args.binary.resolve())
    files = collect_files(app_dir, manifest)
    installed_kib = max(1, sum(len(data) for data, _ in files.values()) // 1024)
    control = {"control": (control_text(manifest, installed_kib).encode("utf-8"), 0o644)}
    deb = ar_archive([
        ("debian-binary", b"2.0\n"),
        ("control.tar.gz", tar_gz(control)),
        ("data.tar.gz", tar_gz(files)),
    ])
    out_dir = (args.out or app_dir / "packages").resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / f"{manifest['id']}_{manifest['version']}_arm64.deb"
    out.write_bytes(deb)
    print(f"package_app: wrote {out}")
    for path in sorted(files):
        print(f"  /{path}")
    print(f"Install on the device:  scp {out.name} pi@<device>:  &&  ssh pi@<device> sudo dpkg -i {out.name}")


if __name__ == "__main__":
    main()
