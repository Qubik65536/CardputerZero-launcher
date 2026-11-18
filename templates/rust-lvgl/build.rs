// SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
// SPDX-License-Identifier: MIT

//! Links the app against the LVGL runtime (LVGL 9.5 + cp0_lvgl + cp0_app.h),
//! built once per machine by `scripts/lvgl-runtime/build.sh desktop|device`.
//!
//! The runtime writes its link flags to `out/<desktop|device>/ldflags.txt`, one
//! per line; every line becomes a linker argument here. The device runtime is
//! used when cross-compiling for aarch64 Linux
//! (`cargo build --target aarch64-unknown-linux-gnu`), the desktop one otherwise.
//!
//! Environment overrides:
//!   CP0_LVGL_RUNTIME=<dir>         the scripts/lvgl-runtime directory, when the app
//!                                  does not live two levels below the repository
//!   CP0_LVGL_TARGET=desktop|device which runtime to link, e.g. `device` when
//!                                  building on the CardputerZero itself

use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process;

/// Which runtime to link: "device" when cross-compiling for the CardputerZero.
fn runtime_kind() -> String {
    if let Ok(kind) = env::var("CP0_LVGL_TARGET") {
        return kind;
    }
    let target = env::var("TARGET").unwrap_or_default();
    let host = env::var("HOST").unwrap_or_default();
    let device = target.starts_with("aarch64") && target.contains("linux") && target != host;
    if device { "device" } else { "desktop" }.to_string()
}

/// scripts/lvgl-runtime: from CP0_LVGL_RUNTIME, or two levels up (templates/<name>
/// and projects/<Name> both sit there).
fn runtime_dir() -> PathBuf {
    if let Ok(dir) = env::var("CP0_LVGL_RUNTIME") {
        return PathBuf::from(dir);
    }
    let manifest = PathBuf::from(env::var("CARGO_MANIFEST_DIR").expect("cargo sets CARGO_MANIFEST_DIR"));
    manifest.join("../../scripts/lvgl-runtime")
}

fn fail(message: &str) -> ! {
    eprintln!("error: {message}");
    println!("cargo:warning={message}");
    process::exit(1);
}

/// Rebuild (and relink) when the runtime's static libraries change, e.g. after
/// running build.sh again: link arguments alone are not tracked by cargo.
fn watch_static_libraries(flags: &[&str]) {
    let directories: Vec<&str> = flags.iter().filter_map(|flag| flag.strip_prefix("-L")).collect();
    for name in flags.iter().filter_map(|flag| flag.strip_prefix("-l")) {
        for directory in &directories {
            let library = Path::new(directory).join(format!("lib{name}.a"));
            if library.exists() {
                println!("cargo:rerun-if-changed={}", library.display());
            }
        }
    }
}

fn main() {
    println!("cargo:rerun-if-env-changed=CP0_LVGL_RUNTIME");
    println!("cargo:rerun-if-env-changed=CP0_LVGL_TARGET");
    let kind = runtime_kind();
    let runtime = runtime_dir();
    let out = runtime.join("out").join(&kind);
    let ldflags = out.join("ldflags.txt");
    println!("cargo:rerun-if-changed={}", ldflags.display());

    let Ok(text) = fs::read_to_string(&ldflags) else {
        fail(&format!(
            "the LVGL runtime for {kind} is not built ({} is missing). \
             Run `scripts/lvgl-runtime/build.sh {kind}` from the repository root first \
             (see scripts/lvgl-runtime/README.md).",
            ldflags.display()
        ));
    };
    let flags: Vec<&str> = text.lines().map(str::trim).filter(|line| !line.is_empty()).collect();
    for flag in &flags {
        println!("cargo:rustc-link-arg={flag}");
    }
    watch_static_libraries(&flags);
}
