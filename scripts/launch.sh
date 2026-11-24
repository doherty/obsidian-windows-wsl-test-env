#!/usr/bin/env bash
# Run as your normal WSL user after reset-vault.sh:
#   bash <skill>/scripts/launch.sh [-i N]
#
# Starts Xvfb on the instance's display and Obsidian on it with the throwaway
# profile. WSLg's DISPLAY/WAYLAND_DISPLAY are cleared so no window can reach the
# Windows desktop. Chromium remote debugging listens on 127.0.0.1:<port>, which
# WSL forwards to Windows localhost, so cdp.mjs can drive the app.
# Re-running restarts this instance's Obsidian (Xvfb is reused).
set -euo pipefail
. "$(dirname "$0")/env.sh"
obs_test_init "$@"

if [ ! -f "$OBS_TEST_VAULT/$OBS_TEST_MARKER" ]; then
	echo "No throwaway vault at $OBS_TEST_VAULT; run reset-vault.sh -i $OBS_TEST_INSTANCE first." >&2
	exit 1
fi

export DISPLAY="$OBS_TEST_DISPLAY"
unset WAYLAND_DISPLAY XDG_SESSION_TYPE
# Keep WSLg out entirely (its runtime socket dir would otherwise be discovered).
export XDG_RUNTIME_DIR="$OBS_TEST_ROOT/runtime"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

xvfb_running() { pgrep -f "Xvfb $OBS_TEST_DISPLAY( |$)" >/dev/null; }
if ! xvfb_running; then
	setsid nohup Xvfb "$OBS_TEST_DISPLAY" -screen 0 1600x1000x24 -nolisten tcp >"$OBS_TEST_ROOT/xvfb.log" 2>&1 &
	sleep 1
	if ! xvfb_running; then
		echo "Xvfb did not start on $OBS_TEST_DISPLAY:" >&2
		cat "$OBS_TEST_ROOT/xvfb.log" >&2
		exit 1
	fi
fi

if obs_test_stop_obsidian; then echo "Restarting instance $OBS_TEST_INSTANCE"; fi

# If anything still answers on our port, it belongs to someone else (another
# instance or a browser). Obsidian would fail to bind and cdp.mjs would end up
# driving that other program, so stop here instead.
port_answers() { curl -fs -m 2 "http://127.0.0.1:$CDP_PORT/json/version" >/dev/null 2>&1; }
if port_answers; then
	echo "Port $CDP_PORT is already in use by another program; refusing to launch instance $OBS_TEST_INSTANCE." >&2
	echo "Pick a free instance (status.sh lists them) or stop whatever holds the port." >&2
	exit 1
fi

LOG="$OBS_TEST_ROOT/obsidian.log"
setsid nohup obsidian \
	--user-data-dir="$OBS_TEST_PROFILE" \
	--remote-debugging-port="$CDP_PORT" \
	--disable-gpu \
	>"$LOG" 2>&1 &

# Ready means: our own process logged that it bound the port, and the main
# window target exists. The log line proves the port is ours, not a leftover.
ready=0
for _ in $(seq 1 60); do
	if ! obs_test_running; then break; fi
	if grep -q "DevTools listening on ws://127.0.0.1:$CDP_PORT/" "$LOG" 2>/dev/null &&
		curl -fs -m 2 "http://127.0.0.1:$CDP_PORT/json/list" | grep -q 'app://obsidian.md/index.html'; then
		ready=1
		break
	fi
	sleep 0.5
done
if [ "$ready" -ne 1 ]; then
	echo "Obsidian did not come up on port $CDP_PORT; last lines of $LOG:" >&2
	tail -20 "$LOG" >&2
	exit 1
fi
echo "Instance $OBS_TEST_INSTANCE: Obsidian is running hidden on $OBS_TEST_DISPLAY; CDP on 127.0.0.1:$CDP_PORT"
