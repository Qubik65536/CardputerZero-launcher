#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
# SPDX-License-Identifier: MIT
"""Turn the smoke program's compile and link commands into flag files.

    export_flags.py <scons log> <work dir> <out dir> <Darwin|Linux|device>

build.sh calls this after building. The SDK prints every command when
CONFIG_COMMPILE_DEBUG=1; the commands that compile and link cp0_app_smoke.c are
exactly what any other program needs to use LVGL and cp0_app.h. This writes, in
<out dir>:

    cflags.txt    one argument per line: -I and -D for lvgl/lvgl.h and cp0_app.h
    ldflags.txt   one argument per line: the libraries, in link order
    cflags.sexp   the same, for dune (:include)
    ldflags.sexp  the same for dune's link_flags, as -ccopt / -cclib pairs

Relative paths become absolute, so the files work from any directory.
"""

import shlex
import sys
from pathlib import Path

SMOKE = "cp0-app-smoke"


def find_command(log, marker):
    for line in log.splitlines():
        if marker in line:
            return shlex.split(line)
    sys.exit(f"export_flags: no command containing {marker!r} in the build log")


def absolute(path, work):
    candidate = Path(path)
    return str(candidate if candidate.is_absolute() else (work / candidate).resolve())


def compile_flags(command, work):
    flags = []
    for argument in command:
        if argument.startswith("-I"):
            directory = absolute(argument[2:], work)
            if Path(directory).is_dir() and "-I" + directory not in flags:
                flags.append("-I" + directory)
        elif argument.startswith("-DLV_CONF_KCONFIG_EXTERNAL_INCLUDE="):
            header = argument.split("=", 1)[1].strip('"')
            flags.append(f'-DLV_CONF_KCONFIG_EXTERNAL_INCLUDE="{absolute(header, work)}"')
        elif argument.startswith("-D"):
            flags.append(argument)
    return flags


def link_flags(command, work, platform):
    flags = []
    arguments = iter(command[1:])  # skip the compiler driver
    for argument in arguments:
        if argument == "-o":
            next(arguments)  # the smoke program itself
        elif argument.endswith(".a") and SMOKE in argument:
            continue  # the smoke program's own code
        elif argument.startswith("-L"):
            directory = absolute(argument[2:], work)
            if Path(directory).is_dir() and "-L" + directory not in flags:
                flags.append("-L" + directory)
        elif argument.startswith(("-Wl,-rpath-link,", "--sysroot=", "-B")):
            flags.append(argument)  # sysroot search paths, for gcc-driven linkers
        elif argument.startswith("-") or argument.endswith((".so", ".a")) or ".so." in argument:
            flags.append(argument if argument.startswith("-") else absolute(argument, work))
    # Shared libraries named by path (the device's libstdc++.so.6) go last: linkers
    # using --as-needed drop a library that comes before the archives needing it.
    shared = [flag for flag in flags if ".so." in flag and not flag.startswith("-")]
    flags = [flag for flag in flags if flag not in shared] + shared
    # What the g++/clang++ driver adds by itself: the C++ runtime, libm, and on
    # Linux libgcc (aarch64 atomics helpers such as __aarch64_cas4_acq_rel).
    flags += {"Darwin": ["-lc++"], "Linux": ["-lstdc++", "-lm", "-lgcc"], "device": ["-lm", "-lgcc"]}[platform]
    return flags


def quote(argument):
    return '"' + argument.replace("\\", "\\\\").replace('"', '\\"') + '"'


def is_library(argument):
    return argument.startswith("-l") or argument.endswith((".a", ".so")) or ".so." in argument


def sexp(arguments):
    return "(" + " ".join(quote(argument) for argument in arguments) + ")\n"


def ocaml_link_sexp(arguments):
    """ocamlfind/dune pass C linker arguments as -cclib (libraries) or -ccopt (options)."""
    pairs = []
    for argument in arguments:
        pairs += ["-cclib" if is_library(argument) else "-ccopt", quote(argument)]
    return "(" + " ".join(pairs) + ")\n"


def main():
    log_path, work, out, platform = sys.argv[1:5]
    log = Path(log_path).read_text(encoding="utf-8", errors="replace")
    work, out = Path(work).resolve(), Path(out).resolve()
    cflags = compile_flags(find_command(log, "cp0_app_smoke.c.o -c"), work)
    ldflags = link_flags(find_command(log, f"-o build/{SMOKE}/{SMOKE} "), work, platform)
    (out / "cflags.txt").write_text("\n".join(cflags) + "\n")
    (out / "ldflags.txt").write_text("\n".join(ldflags) + "\n")
    (out / "cflags.sexp").write_text(sexp(cflags))
    (out / "ldflags.sexp").write_text(ocaml_link_sexp(ldflags))
    print(f"export_flags: wrote {out}/cflags.txt and ldflags.txt ({len(cflags)} + {len(ldflags)} flags)")


if __name__ == "__main__":
    main()
