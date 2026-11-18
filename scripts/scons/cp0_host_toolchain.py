# SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
# SPDX-License-Identifier: MIT

"""Host toolchain fix-ups shared by the SCons projects under projects/.

The SDK build (SDK/tools/scons/project.py) only extends the SCons PATH with
CONFIG_TOOLCHAIN_PATH on hosts it reports as "posix". macOS reports "darwin",
and SCons never inherits the interactive shell PATH, so a Homebrew cross
compiler such as /opt/homebrew/bin/aarch64-linux-gnu-g++ is "command not found"
unless the profile hard-codes CONFIG_TOOLCHAIN_PATH.

Call configure_host_toolchain() from a project SConstruct *after*
CONFIG_DEFAULT_FILE is chosen and *before* the SDK project.py is loaded.
Values already present in the environment always win (the SDK never overrides
an existing CONFIG_* environment variable), so users can still export their
own CONFIG_TOOLCHAIN_PATH / CONFIG_GCC_DUMPMACHINE.
"""

import os
import platform
import re
import shutil
from pathlib import Path


def _profile_value(profile_text, key):
    match = re.search(r'^CONFIG_%s="?([^"\n]*)"?\s*$' % re.escape(key), profile_text, re.M)
    return match.group(1) if match else None


def configure_host_toolchain(defaults_file):
    """Make cross toolchains from the user's PATH visible to SCons on macOS."""
    if platform.system() != "Darwin":
        return
    profile_path = Path(defaults_file)
    if not profile_path.exists():
        return
    profile_text = profile_path.read_text(encoding="utf-8")
    prefix = _profile_value(profile_text, "TOOLCHAIN_PREFIX")
    if not prefix:
        # Native build: Apple clang is reachable through /usr/bin already.
        return

    if "CONFIG_TOOLCHAIN_PATH" not in os.environ and not _profile_value(profile_text, "TOOLCHAIN_PATH"):
        compiler = shutil.which(prefix + "gcc")
        if compiler:
            os.environ["CONFIG_TOOLCHAIN_PATH"] = str(Path(compiler).parent)

    # Homebrew's messense toolchain reports "aarch64-unknown-linux-gnu", but the
    # CardputerZero sysroot uses Debian's multiarch directory names.
    if prefix.startswith("aarch64") and "CONFIG_GCC_DUMPMACHINE" not in os.environ:
        if not _profile_value(profile_text, "GCC_DUMPMACHINE"):
            os.environ["CONFIG_GCC_DUMPMACHINE"] = "aarch64-linux-gnu"


def host_pkg_config(package):
    """Return (cflags, libs, ldflags) for a host library, or None.

    pkg-config describes libraries of the build machine, so this returns None
    whenever a cross sysroot is configured (or the package is unknown) and the
    caller should fall back to its sysroot paths. Homebrew emits -L and
    -Wl,-framework flags next to -l entries; the SDK treats every REQUIREMENTS
    entry as a library, so only -l entries go in `libs` and the rest in
    `ldflags` (put those in a component's LDFLAGS).
    """
    import subprocess

    if os.environ.get("CONFIG_TOOLCHAIN_SYSROOT"):
        return None
    try:
        cflags = subprocess.check_output(["pkg-config", "--cflags", package], text=True).split()
        flags = subprocess.check_output(["pkg-config", "--libs", package], text=True).split()
    except (OSError, subprocess.CalledProcessError):
        return None
    return (cflags,
            [flag for flag in flags if flag.startswith("-l")],
            [flag for flag in flags if not flag.startswith("-l")])
