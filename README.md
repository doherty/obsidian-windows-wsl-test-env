# obsidian-windows-wsl-test-env

An [Agent Skill](https://docs.claude.com/en/docs/claude-code/skills) that lets Claude (or any agent that reads `SKILL.md`) test an Obsidian plugin in a real, running Obsidian on Windows, without touching your vaults and without opening a window on your desktop.

It runs the Linux build of Obsidian in WSL on a virtual display (Xvfb), with a separate profile and a throwaway vault, and drives it from Windows over the Chrome DevTools Protocol. The agent can install a plugin build, run commands, fill in modals, read plugin state, take screenshots and switch to the mobile layout.

## Requirements

- Windows 10 or 11 with WSL 2 and an Ubuntu (or Debian) distro
- Node.js 22 or newer on Windows
- An Obsidian plugin repo that builds `main.js` and `manifest.json` (and optionally `styles.css`) in its root

## Install

Clone into your personal skills folder:

```powershell
git clone https://github.com/doherty/obsidian-windows-wsl-test-env "$env:USERPROFILE\.claude\skills\obsidian-windows-wsl-test-env"
```

Then install Obsidian and Xvfb inside WSL once (it asks for your WSL password via root):

```powershell
wsl -d Ubuntu -u root -- bash "/mnt/c/Users/$env:USERNAME/.claude/skills/obsidian-windows-wsl-test-env/scripts/install.sh"
```

The agent can also do this step for you the first time it uses the skill.

## Use

Ask your agent to check a plugin change in Obsidian, for example "build the plugin and check that the new command opens the modal, with a screenshot". The skill covers the rest: build, reset the throwaway vault, launch, accept the trust prompt, drive, screenshot and stop.

You can also run the scripts by hand. See [SKILL.md](SKILL.md) for the full workflow.

| Script | Runs in | What it does |
| --- | --- | --- |
| `scripts/install.sh` | WSL, as root | Installs Xvfb, jq and the official Obsidian `.deb` (latest, or a version you pass) |
| `scripts/reset-vault.sh [repo]` | WSL | Recreates the throwaway vault and profile and installs the plugin build |
| `scripts/launch.sh` | WSL | Starts Xvfb and Obsidian hidden, with CDP on `127.0.0.1:9222` |
| `scripts/stop.sh` | WSL | Stops Obsidian and Xvfb |
| `scripts/cdp.mjs` | Windows | `eval` code in the renderer, `shot` a screenshot, or send a raw `cdp` call |
| `scripts/examples/smoke.js` | via `cdp.mjs` | Accepts the trust prompt and reports loaded plugins |
| `scripts/examples/mobile-width.js` | via `cdp.mjs` | Switches to a phone-sized window and the mobile layout |

## Safety

- Everything lives under `~/obsidian-test` inside WSL (configurable with `OBS_TEST_ROOT`). The profile knows only the throwaway vault.
- `reset-vault.sh` deletes that folder only if it is new, empty or carries the `.obsidian-throwaway-test-vault` marker, and refuses `/`, your home folder and Windows drives.
- `cdp.mjs` refuses to act unless the connected vault has the marker and lives on the WSL filesystem, so it cannot drive your everyday Obsidian even if it is listening on the same port.
- WSLg is bypassed, so no Obsidian window appears on your desktop.

## License

[MIT](LICENSE)
