#!/usr/bin/env bash
# One-time setup, run as root inside WSL (Ubuntu):
#   sudo bash <skill>/scripts/install.sh [obsidian-version]
#
# Installs a virtual X display (Xvfb), jq and the official Obsidian Linux package
# from github.com/obsidianmd/obsidian-releases. With no version argument the
# latest release is used. Obsidian's runtime libraries come from the .deb's own
# declared dependencies; the final ldd check reports any it fails to declare.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

if [ "$(id -u)" -ne 0 ]; then
	echo "Run as root: sudo bash <skill>/scripts/install.sh [obsidian-version]" >&2
	exit 1
fi

echo '==> Installing Xvfb and jq'
apt-get update -qq
apt-get install -y -qq curl ca-certificates xvfb xauth jq

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
	VERSION="$(curl -fsSL https://api.github.com/repos/obsidianmd/obsidian-releases/releases/latest |
		jq -r '.tag_name' | sed 's/^v//')"
fi
DEB="obsidian_${VERSION}_amd64.deb"
URL="https://github.com/obsidianmd/obsidian-releases/releases/download/v${VERSION}/${DEB}"

echo "==> Installing Obsidian ${VERSION}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fsSL -o "$TMP/$DEB" "$URL"
dpkg-deb -f "$TMP/$DEB" Package Version Maintainer
apt-get install -y -qq "$TMP/$DEB"

echo '==> Checking for missing shared libraries'
if ldd /opt/Obsidian/obsidian | grep 'not found'; then
	echo 'The Obsidian package did not pull in the libraries above (an upstream packaging bug).' >&2
	echo 'Find the owning package with "apt-file search <lib>", install it with apt, and re-run.' >&2
	exit 1
fi
echo "Done: $(command -v obsidian)"
