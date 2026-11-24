#!/usr/bin/env bash
# Run as your normal WSL user (not root):
#   bash <skill>/scripts/reset-vault.sh [-i N] [plugin-repo] [data.json]
#
# Deletes and recreates the instance's root (instance 0: ~/obsidian-test) with a
# throwaway vault and a separate Obsidian profile that knows only that vault, then
# installs the plugin build (main.js, manifest.json, styles.css if present) from
# the given repo/worktree. It defaults to the current directory; use a WSL path
# (/mnt/c/...) or forward slashes. Build the plugin there first.
#
# data.json, if given, is copied in as the plugin's saved settings. A file avoids
# passing JSON through wsl's command line, whose shell would eat the quotes.
# OBS_TEST_PLUGIN_DATA='{"debugMode":true}' in the environment also works.
#
# It refuses to touch a running instance: stop it first with stop.sh, and only
# if it's yours.
set -euo pipefail
. "$(dirname "$0")/env.sh"
obs_test_init "$@"
set -- "${OBS_TEST_ARGS[@]}"

WORKTREE="${1:-$PWD}"
DATA_FILE="${2:-}"
case "$WORKTREE" in
	[A-Za-z]:\\* | [A-Za-z]:/*) WORKTREE="$(wslpath -u "$WORKTREE")" ;;
esac
for f in main.js manifest.json; do
	if [ ! -f "$WORKTREE/$f" ]; then
		echo "Missing $WORKTREE/$f; build the plugin first." >&2
		exit 1
	fi
done

# The plugin id becomes a folder name, so a hostile or broken manifest must not
# be able to point it elsewhere (e.g. "../../x") or break the JSON written below.
PLUGIN_ID="$(jq -er '.id | strings' "$WORKTREE/manifest.json")" || {
	echo "$WORKTREE/manifest.json has no string \"id\"." >&2
	exit 1
}
if ! [[ "$PLUGIN_ID" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
	echo "Refusing plugin id '$PLUGIN_ID': use letters, digits, '.', '_' and '-' only." >&2
	exit 1
fi
PLUGIN_VERSION="$(jq -r '.version // "?"' "$WORKTREE/manifest.json")"

if [ -n "$DATA_FILE" ]; then
	case "$DATA_FILE" in
		[A-Za-z]:\\* | [A-Za-z]:/*) DATA_FILE="$(wslpath -u "$DATA_FILE")" ;;
	esac
	jq -e . "$DATA_FILE" >/dev/null || { echo "$DATA_FILE is not valid JSON." >&2; exit 1; }
elif [ -n "${OBS_TEST_PLUGIN_DATA:-}" ]; then
	printf '%s' "$OBS_TEST_PLUGIN_DATA" | jq -e . >/dev/null || { echo 'OBS_TEST_PLUGIN_DATA is not valid JSON.' >&2; exit 1; }
fi

# Safety: this script deletes OBS_TEST_ROOT. Only ever delete a folder this
# script created (it holds the throwaway marker) or one that is new or empty.
refuse() {
	echo "Refusing to reset $OBS_TEST_ROOT: $1" >&2
	exit 1
}
OBS_TEST_ROOT="$(realpath -m -- "$OBS_TEST_ROOT")"
OBS_TEST_VAULT="$OBS_TEST_ROOT/vault"
OBS_TEST_PROFILE="$OBS_TEST_ROOT/profile"
HOME_REAL="$(realpath -m -- "$HOME")"
case "$OBS_TEST_ROOT" in
	/mnt/*) refuse "it must be inside the WSL filesystem, not on a Windows drive" ;;
esac
if [ "$(stat -f -c %T -- "$(dirname -- "$OBS_TEST_ROOT")" 2>/dev/null)" = v9fs ]; then
	refuse "it is on a Windows drive (9p mount), not the WSL filesystem"
fi
if [ "$OBS_TEST_ROOT" = / ] || [ "$OBS_TEST_ROOT" = "$HOME_REAL" ]; then
	refuse "it is / or your home folder"
fi
case "$HOME_REAL/" in
	"$OBS_TEST_ROOT"/*) refuse "it contains your home folder" ;;
esac
if [ -e "$OBS_TEST_ROOT" ] && [ ! -d "$OBS_TEST_ROOT" ]; then
	refuse "it is not a folder"
fi
if [ -d "$OBS_TEST_ROOT" ] && [ -n "$(ls -A -- "$OBS_TEST_ROOT")" ] && [ ! -f "$OBS_TEST_VAULT/$OBS_TEST_MARKER" ]; then
	refuse "it is not empty and has no $OBS_TEST_MARKER marker, so this script did not create it"
fi
if obs_test_running; then
	refuse "instance $OBS_TEST_INSTANCE is running. If you started it, run stop.sh -i $OBS_TEST_INSTANCE first; if another session did, pick a free instance (status.sh lists them)"
fi

PLUGIN_DIR="$OBS_TEST_VAULT/.obsidian/plugins/$PLUGIN_ID"

rm -rf -- "$OBS_TEST_ROOT"
mkdir -p "$PLUGIN_DIR" "$OBS_TEST_PROFILE"

# Profile: register only the throwaway vault and open it on launch.
jq -n --arg path "$OBS_TEST_VAULT" --argjson ts "$(date +%s)000" \
	'{vaults: {throwawaytestvault: {path: $path, ts: $ts, open: true}}, updateDisabled: true}' \
	>"$OBS_TEST_PROFILE/obsidian.json"

# Plugin build, enabled, with optional seeded settings.
cp "$WORKTREE/main.js" "$WORKTREE/manifest.json" "$PLUGIN_DIR/"
if [ -f "$WORKTREE/styles.css" ]; then cp "$WORKTREE/styles.css" "$PLUGIN_DIR/"; fi
jq -n --arg id "$PLUGIN_ID" '[$id]' >"$OBS_TEST_VAULT/.obsidian/community-plugins.json"
if [ -n "$DATA_FILE" ]; then
	cp "$DATA_FILE" "$PLUGIN_DIR/data.json"
elif [ -n "${OBS_TEST_PLUGIN_DATA:-}" ]; then
	printf '%s\n' "$OBS_TEST_PLUGIN_DATA" >"$PLUGIN_DIR/data.json"
fi

printf 'Throwaway Obsidian plugin test vault. Safe to delete.\n' >"$OBS_TEST_VAULT/$OBS_TEST_MARKER"
printf '# Test vault\n\nThrowaway vault for automated plugin testing.\n' >"$OBS_TEST_VAULT/Welcome.md"
printf '%s %s from %s\n' "$PLUGIN_ID" "$PLUGIN_VERSION" "$WORKTREE" >"$OBS_TEST_ROOT/plugin.txt"

echo "Reset instance $OBS_TEST_INSTANCE ($OBS_TEST_ROOT) with $PLUGIN_ID $PLUGIN_VERSION from $WORKTREE"
