/*
 * SPDX-FileCopyrightText: 2026 M5Stack Technology CO LTD
 *
 * SPDX-License-Identifier: MIT
 */

#include "sdl_external_app_runner.hpp"

#include "cp0_esc_exit_policy.hpp"
#include "cp0_esc_state.h"
#include "../cp0_external_process_group.hpp"

#include <chrono>
#include <cstdio>
#include <cstring>
#include <string>
#include <thread>
#include <vector>

#if !defined(_WIN32)
#include <signal.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;
#endif

extern "C" const char *const *__attribute__((weak)) cp0_sdl_external_app_env(void)
{
    return nullptr;
}
extern "C" void __attribute__((weak)) cp0_sdl_external_app_begin(int pid) { (void)pid; }
extern "C" int __attribute__((weak)) cp0_sdl_external_app_tick(void) { return 50; }
extern "C" void __attribute__((weak)) cp0_sdl_external_app_end(void) {}

namespace sdl_external_app_runner {

extern "C" void __attribute__((weak)) ui_external_esc_hint(int visible) { (void)visible; }

namespace {
std::uint64_t monotonic_ms()
{
    return static_cast<std::uint64_t>(
        std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now().time_since_epoch()).count());
}

#if !defined(_WIN32)
/* The current environment with `extra` ("NAME=value", NULL-terminated) added or
 * replacing same-named entries. Built before fork() so the child only execs. */
std::vector<std::string> merged_environment(const char *const *extra)
{
    std::vector<std::string> merged;
    for (char **entry = environ; entry && *entry; ++entry) {
        const char *equals = std::strchr(*entry, '=');
        const std::size_t name_length = equals ? static_cast<std::size_t>(equals - *entry) : 0;
        bool replaced = false;
        for (const char *const *added = extra; *added && name_length; ++added)
            if (std::strncmp(*added, *entry, name_length + 1) == 0) replaced = true;
        if (!replaced) merged.emplace_back(*entry);
    }
    for (const char *const *added = extra; *added; ++added) merged.emplace_back(*added);
    return merged;
}
#endif
} // namespace

int run(const char *command)
{
#if defined(_WIN32)
    (void)command;
    return -1;
#else
    const char *const *extra_env = cp0_sdl_external_app_env();
    std::vector<std::string> env_storage;
    std::vector<char *> envp;
    if (extra_env) {
        env_storage = merged_environment(extra_env);
        for (std::string &entry : env_storage) envp.push_back(&entry[0]);
        envp.push_back(nullptr);
    }

    const bool subreaper = cp0_process_group::enable_subreaper();
    const pid_t pid = fork();
    if (pid < 0) return -1;
    if (pid == 0) {
        setpgid(0, 0);
        if (extra_env) {
            char *const argv[] = {const_cast<char *>("sh"), const_cast<char *>("-c"),
                                  const_cast<char *>(command), nullptr};
            execve("/bin/sh", argv, envp.data());
        } else {
            execlp("/bin/sh", "sh", "-c", command, static_cast<char *>(nullptr));
        }
        _exit(127);
    }

    setpgid(pid, pid);
    std::fprintf(stderr, "[process] external app leader=%d pgid=%d subreaper=%d\n",
                 static_cast<int>(pid), static_cast<int>(pid), subreaper ? 1 : 0);
    cp0_sdl_external_app_begin(static_cast<int>(pid));

    int status = 0;
    bool leader_reaped = false;
    cp0_esc_exit_policy::StateMachine esc_policy;
    while (true) {
        cp0_process_group::reap_available(pid, pid, status, leader_reaped);
        if (!cp0_process_group::exists(pid)) break;

        const auto decision = esc_policy.update(
            monotonic_ms(), cp0_esc_state_read() != 0);
        if (decision.show_hint) ui_external_esc_hint(1);
        if (decision.hide_hint) ui_external_esc_hint(0);
        if (decision.send_terminate) {
            std::fprintf(stderr, "[process] ESC timeout: SIGTERM pgid=%d\n",
                         static_cast<int>(pid));
            killpg(pid, SIGTERM);
        }
        if (decision.send_kill) {
            std::fprintf(stderr, "[process] grace timeout: SIGKILL pgid=%d\n",
                         static_cast<int>(pid));
            killpg(pid, SIGKILL);
        }
        const int sleep_ms = cp0_sdl_external_app_tick();
        std::this_thread::sleep_for(std::chrono::milliseconds(sleep_ms > 0 ? sleep_ms : 1));
    }

    cp0_sdl_external_app_end();
    if (esc_policy.finish().hide_hint) ui_external_esc_hint(0);
    cp0_process_group::reap_available(pid, pid, status, leader_reaped);
    std::fprintf(stderr, "[process] external app group drained pgid=%d leader_reaped=%d\n",
                 static_cast<int>(pid), leader_reaped ? 1 : 0);
    cp0_esc_state_reset();
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
#endif
}

} // namespace sdl_external_app_runner
