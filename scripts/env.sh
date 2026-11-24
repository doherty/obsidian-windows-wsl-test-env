#!/usr/bin/env bash
# Shared settings for the hidden WSL test environment. Sourced by the other
# scripts in this folder, which then call: obs_test_init "$@"; set -- "${OBS_TEST_ARGS[@]}"
#
# Pick an instance with -i N as the first argument (default 0). Each instance has
# its own root, X display and CDP port, so sessions can run side by side:
#
#   instance  root                  display  CDP port
#   0         ~/obsidian-test       :99      9222
#   N         ~/obsidian-test-N     :99-N    9222+N
#
# The instance is an argument rather than an environment variable on purpose:
# agents' shell tools don't keep environment variables between calls, so a
# setting made in one call would silently fall back to instance 0 in the next.
#
# Expert overrides (take precedence over -i): OBS_TEST_ROOT, OBS_TEST_DISPLAY, CDP_PORT.

# cdp.mjs checks for the same marker name; keep the two in step.
OBS_TEST_MARKER=".obsidian-throwaway-test-vault"

obs_test_init() {
	OBS_TEST_INSTANCE=0
	if [ "${1:-}" = "-i" ]; then
		OBS_TEST_INSTANCE="${2:-}"
		shift 2 || true
	fi
	if ! [[ "$OBS_TEST_INSTANCE" =~ ^([0-9]|[1-4][0-9])$ ]]; then
		echo "Instance must be a number from 0 to 49 (got '$OBS_TEST_INSTANCE')" >&2
		exit 1
	fi
	OBS_TEST_ARGS=("$@")

	local suffix=""
	if [ "$OBS_TEST_INSTANCE" -ne 0 ]; then suffix="-$OBS_TEST_INSTANCE"; fi
	OBS_TEST_ROOT="${OBS_TEST_ROOT:-$HOME/obsidian-test$suffix}"
	OBS_TEST_DISPLAY="${OBS_TEST_DISPLAY:-:$((99 - OBS_TEST_INSTANCE))}"
	CDP_PORT="${CDP_PORT:-$((9222 + OBS_TEST_INSTANCE))}"
	OBS_TEST_VAULT="$OBS_TEST_ROOT/vault"
	OBS_TEST_PROFILE="$OBS_TEST_ROOT/profile"
}

# The ( |$) ending stops .../profile from also matching a path such as .../profile-old.
obs_test_running() {
	pgrep -f -- "--user-data-dir=$OBS_TEST_PROFILE( |$)" >/dev/null
}

# Stops this instance's Obsidian and waits for it to exit, so callers don't race
# it (reset-vault.sh deletes its files next). Returns 1 if it wasn't running.
obs_test_stop_obsidian() {
	pkill -f -- "--user-data-dir=$OBS_TEST_PROFILE( |$)" || return 1
	for _ in $(seq 1 20); do
		obs_test_running || return 0
		sleep 0.25
	done
	pkill -KILL -f -- "--user-data-dir=$OBS_TEST_PROFILE( |$)" || true
	sleep 0.5
}
