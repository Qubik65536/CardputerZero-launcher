#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
# SPDX-License-Identifier: MIT
"""Create a new CardputerZero app from one of the templates in templates/.

    python3 scripts/new_app.py cpp "Weather Station"
    python3 scripts/new_app.py rust "Pixel Pet" --dest ~/code/pixel-pet

Every template is a working app called "Hello Cardputer". The new app is a copy
with each spelling of that name replaced by the matching spelling of yours:

    Hello Cardputer -> Weather Station   (display name, .desktop Name=)
    HelloCardputer  -> WeatherStation    (C++ types, project directory)
    hello-cardputer -> weather-station   (binary / package name)
    hello_cardputer -> weather_station   (Rust crate, Zig/OCaml identifiers)

By default the app goes to projects/<PascalName>, next to the bundled projects;
C++ (SCons) apps must stay there because they use ../../SDK.
"""

import argparse
import random
import re
import shutil
import sys
import zlib
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
TEMPLATES = REPO_ROOT / "templates"
TEMPLATE_WORDS = ["Hello", "Cardputer"]
# Build outputs and caches that must never be copied from a template.
SKIPPED_NAMES = {
    "build", "dist", "target", "_build", "zig-out", ".zig-cache", "__pycache__",
    ".cache", ".venv", "compile_commands.json", "TEMPLATE.md",
}
TEXT_SUFFIXES = {
    "", ".c", ".cc", ".cpp", ".h", ".hpp", ".rs", ".zig", ".zon", ".ml", ".mli",
    ".toml", ".json", ".md", ".mk", ".py", ".sh", ".txt", ".desktop", ".opam",
    ".in", ".yml", ".yaml", ".cfg", ".ini",
}
TEXT_NAMES = {"SConstruct", "Kconfig", "Makefile", "dune", "dune-project", ".gitignore", "Cargo.lock", "Dockerfile"}


def split_words(name):
    """'Weather Station' / 'WeatherStation' / 'weather-station' -> ['Weather', 'Station']."""
    words = []
    for chunk in re.split(r"[\s_\-]+", name.strip()):
        # Split camelCase ("weatherStation") and acronym boundaries ("HTTPTool");
        # digits stay attached to their word ("Tetris3D").
        chunk = re.sub(r"(?<=[a-z0-9])(?=[A-Z][a-z])|(?<=[a-z])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])", " ", chunk)
        words += chunk.split()
    return [word[:1].upper() + word[1:] for word in words if word]


def name_forms(words):
    return {
        "display": " ".join(words),
        "pascal": "".join(words),
        "kebab": "-".join(word.lower() for word in words),
        "snake": "_".join(word.lower() for word in words),
    }


def replacements(new_words):
    old, new = name_forms(TEMPLATE_WORDS), name_forms(new_words)
    # Longest first, so "Hello Cardputer" is handled before any shorter overlap.
    pairs = [(old[key], new[key]) for key in ("display", "pascal", "kebab", "snake")]
    return sorted(pairs, key=lambda pair: -len(pair[0]))


def rename(text, pairs):
    for old, new in pairs:
        text = text.replace(old, new)
    return text


def is_text_file(path):
    return path.suffix in TEXT_SUFFIXES or path.name in TEXT_NAMES


def template_files(template_dir):
    """The template's files: git-tracked ones when possible, so local build
    output never leaks into a new app; otherwise everything not ignored here."""
    import subprocess

    try:
        listed = subprocess.run(["git", "ls-files", "-z", "--", "."], cwd=template_dir, check=True,
                                capture_output=True).stdout.split(b"\0")
        files = [template_dir / name.decode() for name in listed if name]
        if files:
            return sorted(files)
    except (OSError, subprocess.CalledProcessError):
        pass
    return sorted(path for path in template_dir.rglob("*") if path.is_file())


def copy_template(template_dir, dest, pairs):
    for source in template_files(template_dir):
        relative = source.relative_to(template_dir)
        if any(part in SKIPPED_NAMES for part in relative.parts):
            continue
        target = dest / Path(*[rename(part, pairs) for part in relative.parts])
        target.parent.mkdir(parents=True, exist_ok=True)
        data = source.read_bytes()
        if is_text_file(source):
            try:
                data = rename(data.decode("utf-8"), pairs).encode("utf-8")
            except UnicodeDecodeError:
                pass  # not text after all: copy unchanged
        target.write_bytes(data)
        shutil.copymode(source, target)


def refresh_zig_fingerprint(dest, package_name):
    """Zig ties build.zig.zon's .fingerprint to .name: CRC32(name) in the high 32
    bits and a random non-zero id in the low 32 bits. Renaming needs a new one."""
    zon = dest / "build.zig.zon"
    if not zon.exists():
        return
    fingerprint = (zlib.crc32(package_name.encode()) << 32) | random.randint(1, 0xFFFFFFFE)
    text = re.sub(r"\.fingerprint = 0x[0-9a-fA-F]+", f".fingerprint = 0x{fingerprint:016x}", zon.read_text())
    zon.write_text(text)


def available_templates():
    return sorted(path.name for path in TEMPLATES.iterdir() if (path / "TEMPLATE.md").exists())


def parse_args(argv):
    templates = available_templates()
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("template", choices=templates, help="template to start from")
    parser.add_argument("name", help='app name, e.g. "Weather Station"')
    parser.add_argument("--dest", type=Path, help="target directory (default: projects/<PascalName>)")
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    words = split_words(args.name)
    if not words or not words[0][0].isalpha():
        sys.exit(f"new_app: '{args.name}' must start with a letter and contain letters/digits")
    forms = name_forms(words)
    dest = (args.dest or REPO_ROOT / "projects" / forms["pascal"]).expanduser().resolve()
    if dest.exists() and any(dest.iterdir()):
        sys.exit(f"new_app: {dest} already exists and is not empty")
    if args.template == "cpp-lvgl" and dest.parent != (REPO_ROOT / "projects").resolve():
        sys.exit("new_app: cpp-lvgl apps must live directly under projects/ (they build against ../../SDK)")

    copy_template(TEMPLATES / args.template, dest, replacements(words))
    refresh_zig_fingerprint(dest, forms["snake"])
    shown = dest.relative_to(REPO_ROOT) if dest.is_relative_to(REPO_ROOT) else dest
    print(f"Created {forms['display']!r} from templates/{args.template} in {shown}")
    print(f"Next: read {shown}/README.md")


if __name__ == "__main__":
    main()
