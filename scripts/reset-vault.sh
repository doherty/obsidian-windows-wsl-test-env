#!/usr/bin/env bash
# Run as your normal WSL user (not root):
#   bash <skill>/scripts/reset-vault.sh [plugin-repo]
#
# Deletes and recreates $OBS_TEST_ROOT (default ~/obsidian-test) with a throwaway vault
# and a separate Obsidian profile that knows only that vault, then installs the
# plugin build (main.js, manifest.json, styles.css if present) from the given
# repo/worktree. It defaults to the current directory; use a WSL path (/mnt/c/...)
# or forward slashes. Build the plugin there first.
#
# Optional: OBS_TEST_PLUGIN_DATA='{"debugMode":true}' seeds the plugin's data.json.
set -euo pipefail
. "$(dirname "$0")/env.sh"

WORKTREE="${1:-$PWD}"
case "$WORKTREE" in
	[A-Za-z]:\\* | [A-Za-z]:/*) WORKTREE="$(wslpath -u "$WORKTREE")" ;;
esac
for f in main.js manifest.json; do
	if [ ! -f "$WORKTREE/$f" ]; then
		echo "Missing $WORKTREE/$f; build the plugin first." >&2
		exit 1
	fi
done

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

if pgrep -f -- "--user-data-dir=$OBS_TEST_PROFILE" >/dev/null; then
	echo "Stopping the running test Obsidian first"
	pkill -f -- "--user-data-dir=$OBS_TEST_PROFILE" || true
	sleep 2
fi

PLUGIN_ID="$(jq -r .id "$WORKTREE/manifest.json")"
PLUGIN_DIR="$OBS_TEST_VAULT/.obsidian/plugins/$PLUGIN_ID"

rm -rf "$OBS_TEST_ROOT"
mkdir -p "$PLUGIN_DIR" "$OBS_TEST_PROFILE"

# Profile: register only the throwaway vault and open it on launch.
cat >"$OBS_TEST_PROFILE/obsidian.json" <<EOF
{"vaults":{"throwawaytestvault":{"path":"$OBS_TEST_VAULT","ts":$(date +%s)000,"open":true}},"updateDisabled":true}
EOF

# Plugin build, enabled, with optional seeded settings.
cp "$WORKTREE/main.js" "$WORKTREE/manifest.json" "$PLUGIN_DIR/"
if [ -f "$WORKTREE/styles.css" ]; then cp "$WORKTREE/styles.css" "$PLUGIN_DIR/"; fi
echo "[\"$PLUGIN_ID\"]" >"$OBS_TEST_VAULT/.obsidian/community-plugins.json"
if [ -n "${OBS_TEST_PLUGIN_DATA:-}" ]; then
	printf '%s\n' "$OBS_TEST_PLUGIN_DATA" >"$PLUGIN_DIR/data.json"
fi

printf 'Throwaway Obsidian plugin test vault. Safe to delete.\n' >"$OBS_TEST_VAULT/$OBS_TEST_MARKER"
printf '# Test vault\n\nThrowaway vault for automated plugin testing.\n' >"$OBS_TEST_VAULT/Welcome.md"

echo "Reset $OBS_TEST_ROOT with $PLUGIN_ID $(jq -r .version "$WORKTREE/manifest.json") from $WORKTREE"
