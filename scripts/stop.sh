#!/usr/bin/env bash
# Stops one hidden test instance (Obsidian and its Xvfb display):
#   bash <skill>/scripts/stop.sh [-i N]
# Only stop an instance you started: another session may be using a different one.
set -uo pipefail
. "$(dirname "$0")/env.sh"
obs_test_init "$@"

if obs_test_stop_obsidian; then echo "Stopped Obsidian (instance $OBS_TEST_INSTANCE, $OBS_TEST_PROFILE)"; fi
if pkill -f "Xvfb $OBS_TEST_DISPLAY( |$)"; then echo "Stopped Xvfb $OBS_TEST_DISPLAY"; fi
exit 0
