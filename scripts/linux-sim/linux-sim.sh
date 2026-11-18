#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
# SPDX-License-Identifier: MIT
#
# Build, run and test CardputerZero projects in a Linux container.
#
# Why: several projects (LaunchWizard, AppStore, the APPLaunch test suites, ...)
# are Linux-only, and macOS/Windows hosts need somewhere to run them. The
# container gets its own copy of the repository (a Docker volume), so builds in
# it never touch your host build/ and dist/ directories.
#
# GUI apps run under Xvfb and are exported over VNC:
#   macOS:  open vnc://localhost:5900      (password: cardputer)
#   Linux:  any VNC viewer on localhost:5900
#
# Usage: scripts/linux-sim/linux-sim.sh <command> [args]   (see usage below)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
IMAGE="${CP0_LINUX_SIM_IMAGE:-cardputerzero-linux-sim}"
VOLUME="${CP0_LINUX_SIM_VOLUME:-cardputerzero-linux-sim-work}"
VNC_PORT="${CP0_LINUX_SIM_VNC_PORT:-5900}"
VNC_PASSWORD="${CP0_LINUX_SIM_VNC_PASSWORD:-cardputer}"
PROFILE="linux_x86_sdl2_config_defaults.mk"

usage() {
    cat <<EOF
Usage: $(basename "$0") <command> [args]

  build <project>                   Build projects/<project> with its Linux SDL2 profile.
  run <project>                     Build, then run its simulator; view it over VNC
                                    (open vnc://localhost:$VNC_PORT, password: $VNC_PASSWORD).
  shot <project> <out.png> [secs]   Build, run headless for [secs] (default 5) and save
                                    a 320x170 screenshot to <out.png> on the host.
  gui <dir> <command...>            Run any GUI command under VNC, from <dir> inside
                                    the synced repo (e.g. gui projects/MyApp ./build/myapp).
  test <suite>                      Run a Linux test suite:
                                    applaunch | cp0_lvgl | zclaw | launchwizard
  shell                             Interactive shell in the synced repo.
  image                             (Re)build the container image.
  clean                             Delete the container's copy of the repo.

<project> is a directory name under projects/ that has $PROFILE
(APPLaunch, HelloWorld, UserDemo, ZClaw, LaunchWizard, AppStore, Calculator, or your own).
EOF
}

die() {
    echo "linux-sim: $*" >&2
    exit 1
}

require_docker() {
    command -v docker >/dev/null 2>&1 || die "docker not found (install Docker Desktop, OrbStack or docker engine)"
    docker info >/dev/null 2>&1 || die "docker daemon is not running"
}

build_image() {
    echo "linux-sim: building image $IMAGE ..."
    docker build -t "$IMAGE" "$SCRIPT_DIR"
}

ensure_image() {
    docker image inspect "$IMAGE" >/dev/null 2>&1 || build_image
}

# Copy the host checkout into the volume. Build outputs and the cross sysroot are
# excluded (and, being excluded, are kept between runs for incremental builds).
sync_repo() {
    docker run --rm \
        -v "$REPO_ROOT":/src:ro \
        -v "$VOLUME":/work \
        "$IMAGE" \
        rsync -a --delete \
            --exclude '/projects/*/build/' --exclude '/projects/*/dist/' \
            --exclude '/projects/*/main/build/' --exclude '/projects/*/*/build/' \
            --exclude '/projects/*/*/dist/' --exclude '/projects/*/target/' \
            --exclude '/projects/*/zig-out/' --exclude '/projects/*/.zig-cache/' \
            --exclude '/projects/*/_build/' \
            --exclude '/SDK/github_source/static_lib_*' \
            --exclude '.venv/' --exclude '.cache/' --exclude '__pycache__/' \
            /src/ /work/repo/
}

# Run a bash snippet in the container, inside the synced repo.
in_container() {
    local tty_flags=()
    if [ -t 0 ] && [ -t 1 ]; then tty_flags=(-it); fi
    docker run --rm --init ${tty_flags[@]+"${tty_flags[@]}"} \
        -e CONFIG_REPO_AUTOMATION=y \
        -v "$VOLUME":/work \
        "${EXTRA_DOCKER_ARGS[@]+"${EXTRA_DOCKER_ARGS[@]}"}" \
        -w /work/repo \
        "$IMAGE" bash -c "$1"
}

check_project() {
    local project="$1"
    [ -n "$project" ] || die "missing <project>"
    [ -f "$REPO_ROOT/projects/$project/$PROFILE" ] ||
        die "projects/$project has no $PROFILE (only SCons projects are supported; use 'gui' for others)"
}

# Shell snippet: build a SCons project with the Linux SDL2 profile.
build_snippet() {
    cat <<EOF
set -e
cd projects/$1
CONFIG_DEFAULT_FILE=$PROFILE scons -j"\$(nproc)"
EOF
}

# Shell snippet: start Xvfb sized like the device LCD (plus VNC when asked).
display_snippet() {
    local with_vnc="$1"
    cat <<EOF
Xvfb :99 -screen 0 320x170x24 -nolisten tcp >/dev/null 2>&1 &
export DISPLAY=:99
for _ in \$(seq 50); do xdpyinfo >/dev/null 2>&1 && break; sleep 0.1; done
EOF
    if [ "$with_vnc" = vnc ]; then
        cat <<EOF
x11vnc -display :99 -forever -shared -quiet -rfbport 5900 -passwd '$VNC_PASSWORD' >/dev/null 2>&1 &
echo "linux-sim: VNC ready -> open vnc://localhost:$VNC_PORT (password: $VNC_PASSWORD). Ctrl-C to stop."
EOF
    fi
}

# Shell snippet: find the executable the build placed in dist/.
binary_snippet() {
    cat <<'EOF'
bin=$(find dist -maxdepth 1 -type f -perm -u+x | head -n1)
[ -n "$bin" ] || { echo "linux-sim: no executable in dist/" >&2; exit 1; }
EOF
}

cmd_build() {
    check_project "${1:-}"
    sync_repo
    in_container "$(build_snippet "$1")"
}

cmd_run() {
    check_project "${1:-}"
    sync_repo
    EXTRA_DOCKER_ARGS=(-p "127.0.0.1:$VNC_PORT:5900")
    in_container "$(build_snippet "$1")
$(display_snippet vnc)
$(binary_snippet)
cd dist && exec \"./\${bin#dist/}\""
}

cmd_shot() {
    local project="${1:-}" out="${2:-}" secs="${3:-5}"
    check_project "$project"
    [ -n "$out" ] || die "missing <out.png>"
    local out_dir out_name
    out_dir="$(cd "$(dirname "$out")" && pwd)"
    out_name="$(basename "$out")"
    sync_repo
    EXTRA_DOCKER_ARGS=(-v "$out_dir":/out)
    in_container "$(build_snippet "$project")
$(display_snippet none)
$(binary_snippet)
cd dist && \"./\${bin#dist/}\" &
app=\$!
sleep $secs
kill -0 \$app 2>/dev/null || { echo 'linux-sim: app exited early' >&2; exit 1; }
xwd -root -silent | convert xwd:- /out/$out_name
kill -TERM \$app; wait \$app || true
echo \"linux-sim: saved $out\""
}

cmd_gui() {
    local dir="${1:-}"
    [ -n "$dir" ] && [ $# -ge 2 ] || die "usage: gui <dir> <command...>"
    shift
    sync_repo
    EXTRA_DOCKER_ARGS=(-p "127.0.0.1:$VNC_PORT:5900")
    in_container "$(display_snippet vnc)
cd '$dir' && exec $*"
}

cmd_test() {
    local snippet
    case "${1:-}" in
        applaunch) snippet="sh projects/APPLaunch/tests/run_tests.sh" ;;
        cp0_lvgl) snippet="sh ext_components/cp0_lvgl/tests/run_tests.sh" ;;
        zclaw) snippet="cd projects/ZClaw && sh tests/run_tests.sh" ;;
        launchwizard) snippet="cd projects/LaunchWizard && cmake --preset dev && cmake --build --preset dev && ctest --preset dev" ;;
        *) die "unknown suite '${1:-}' (applaunch | cp0_lvgl | zclaw | launchwizard)" ;;
    esac
    sync_repo
    in_container "export PYTHONDONTWRITEBYTECODE=1 TMPDIR=/tmp; $snippet"
}

cmd_shell() {
    sync_repo
    in_container "exec bash"
}

main() {
    local command="${1:-}"
    [ $# -gt 0 ] && shift
    EXTRA_DOCKER_ARGS=()
    case "$command" in
        -h | --help | help | "") usage; exit 0 ;;
    esac
    require_docker
    case "$command" in
        image) build_image ;;
        clean) docker volume rm "$VOLUME" >/dev/null && echo "linux-sim: removed volume $VOLUME" ;;
        *)
            ensure_image
            case "$command" in
                build) cmd_build "$@" ;;
                run) cmd_run "$@" ;;
                shot) cmd_shot "$@" ;;
                gui) cmd_gui "$@" ;;
                test) cmd_test "$@" ;;
                shell) cmd_shell ;;
                *) usage; exit 1 ;;
            esac
            ;;
    esac
}

main "$@"
