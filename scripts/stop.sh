#!/usr/bin/env bash
# Stops the hidden test Obsidian and its Xvfb display:
#   bash <skill>/scripts/stop.sh
set -uo pipefail
. "$(dirname "$0")/env.sh"

pkill -f -- "--user-data-dir=$OBS_TEST_PROFILE" && echo "Stopped Obsidian ($OBS_TEST_PROFILE)"
pkill -f "Xvfb $OBS_TEST_DISPLAY( |$)" && echo "Stopped Xvfb $OBS_TEST_DISPLAY"
exit 0
