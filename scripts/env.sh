#!/usr/bin/env bash
# Shared settings for the hidden WSL test environment. Sourced by the other
# scripts in this folder; override any value through the environment.
#
#   OBS_TEST_ROOT     where the throwaway vault, profile and logs live (default ~/obsidian-test)
#   OBS_TEST_DISPLAY  virtual X display number used by Xvfb (default :99)
#   CDP_PORT          Chrome DevTools Protocol port on localhost (default 9222)
#
# Run a second, independent instance by changing all three, for example:
#   OBS_TEST_ROOT=~/obsidian-test-2 OBS_TEST_DISPLAY=:98 CDP_PORT=9223 bash launch.sh

OBS_TEST_ROOT="${OBS_TEST_ROOT:-$HOME/obsidian-test}"
OBS_TEST_DISPLAY="${OBS_TEST_DISPLAY:-:99}"
CDP_PORT="${CDP_PORT:-9222}"
OBS_TEST_VAULT="$OBS_TEST_ROOT/vault"
OBS_TEST_PROFILE="$OBS_TEST_ROOT/profile"
# cdp.mjs refuses to act on any vault that lacks this marker file.
OBS_TEST_MARKER=".obsidian-throwaway-test-vault"
