#!/usr/bin/env bash
# Lists the hidden test instances that exist in WSL and whether each is running:
#   bash <skill>/scripts/status.sh
# Use it to pick a free instance number before starting, and to check that an
# instance is yours before resetting or stopping it.
set -uo pipefail
. "$(dirname "$0")/env.sh"

found=0
for n in $(seq 0 49); do
	unset OBS_TEST_ROOT OBS_TEST_DISPLAY CDP_PORT
	obs_test_init -i "$n"
	if [ ! -d "$OBS_TEST_ROOT" ] && ! obs_test_running; then continue; fi
	found=1
	state=stopped
	if obs_test_running; then state=running; fi
	plugin="$(cat "$OBS_TEST_ROOT/plugin.txt" 2>/dev/null || echo '?')"
	printf 'instance %-2s  %-7s  display %-4s  port %s  %s  plugin %s\n' \
		"$n" "$state" "$OBS_TEST_DISPLAY" "$CDP_PORT" "$OBS_TEST_ROOT" "$plugin"
done
if [ "$found" -eq 0 ]; then echo 'No test instances; instance 0 is free.'; fi
