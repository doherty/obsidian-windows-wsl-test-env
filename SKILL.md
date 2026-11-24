---
name: obsidian-windows-wsl-test-env
description: Run live tests of an Obsidian plugin on Windows in a hidden, throwaway Obsidian (the Linux build under Xvfb in WSL, driven over the Chrome DevTools Protocol). Use whenever a plugin change needs checking in a real, running Obsidian on a Windows machine, such as UI, commands, modals, settings tabs, events, screenshots or the mobile layout, even if the user just says "try it in Obsidian", "does this actually work" or "take a screenshot of the plugin". It never touches the user's real vaults and no window appears on the desktop. Works for any plugin repo and needs no scripts in it.
---

# Hidden Obsidian test environment (Windows + WSL)

This runs the Linux build of Obsidian inside WSL on a virtual display (Xvfb), with its own profile and a throwaway vault, and drives it from Windows over the Chrome DevTools Protocol (CDP). You get a real Obsidian to test against, without risking the user's notes or putting windows on their screen.

## Ground rules, and why

- **Only ever use the throwaway vault this skill creates.** A test that misbehaves in a real vault can rewrite or delete someone's notes. `cdp.mjs` refuses any vault without the `.obsidian-throwaway-test-vault` marker or outside the WSL filesystem. Never weaken or bypass that guard, and if it refuses, stop and find out why.
- **Keep it invisible.** Don't launch Windows Obsidian, Windows Sandbox or Hyper-V for testing. `launch.sh` clears WSLg's display variables so nothing reaches the desktop, and the user can keep working undisturbed.
- **Don't use the Windows `obsidian` CLI for tests.** It opens the user's last real vault, and its `vault=` argument does not reliably route elsewhere.
- **Leave other sessions' instances alone.** Another agent session may be testing in its own instance. Never reset or stop an instance you didn't start (see "Instances" below).

## Paths

The scripts live in this skill's `scripts/` folder. You need its path in two forms:

- `<win-skill>`: the Windows path, for `node`. For example `C:\Users\<user>\.claude\skills\obsidian-windows-wsl-test-env`.
- `<wsl-skill>`: the same folder as WSL sees it, for `bash`. Swap `C:\` for `/mnt/c/` and every `\` for `/`, giving `/mnt/c/Users/<user>/.claude/skills/obsidian-windows-wsl-test-env`. Always write WSL paths with forward slashes, because `wsl` strips backslashes from arguments.

The commands below use the distro `Ubuntu`. If `wsl -l -q` lists a different Ubuntu or Debian distro, use its name instead. Node 22 or newer must be on the Windows PATH, since `cdp.mjs` uses the built-in `fetch` and `WebSocket`.

## One-time install

Skip this if `wsl -d Ubuntu -- bash -c 'command -v obsidian Xvfb'` prints both paths. Otherwise:

```powershell
wsl -d Ubuntu -u root -- bash <wsl-skill>/scripts/install.sh
```

This installs Xvfb, jq and the latest official Obsidian `.deb`, whose declared dependencies supply its runtime libraries. Pass a version to pin one (tested with 1.15.1 on Ubuntu 26.04). Obsidian publishes the `.deb` for amd64 only, so ARM machines aren't supported. If the final `ldd` check reports missing libraries, the package failed to declare them (an upstream bug; 1.15.1 omits `libgbm1` and `libasound2t64`). Install them with apt and run it again.

## Instances

Each instance is a separate hidden Obsidian with its own root folder, X display and CDP port, so several sessions can test at once. Every script takes the instance as `-i N` (0 to 49; default 0). Instance N lives in `~/obsidian-test-N` (instance 0: `~/obsidian-test`) and listens on port `9222+N`.

At the start of a test session, list the instances:

```powershell
wsl -d Ubuntu -- bash <wsl-skill>/scripts/status.sh
```

Use instance 0 if it's free. If it is running, another session probably owns it, so pick the lowest number that isn't listed and use that number for the rest of the session. Pass `-i N` to **every** command, including `cdp.mjs`: the instance is an argument rather than an environment variable because your shell tool doesn't keep variables between calls, and a forgotten setting would silently hit someone else's instance. The scripts back this up: `reset-vault.sh` refuses to touch a running instance, and `launch.sh` refuses a port that's already taken.

## Each test session

The examples use instance 0. Add `-i N` right after the script name for another instance.

1. **Build the plugin** in the repo or worktree under test. The build must leave `main.js` and `manifest.json` in the repo root, plus `styles.css` if the plugin has one.
2. **Reset** the instance's throwaway vault and install the build into it. Run this from the repo folder: `wsl` keeps the current folder, and the script defaults to it.
   ```powershell
   wsl -d Ubuntu -- bash <wsl-skill>/scripts/reset-vault.sh -i 0
   ```
   Or pass the repo as a `/mnt/c/...` path. To seed the plugin's saved settings, write them to a JSON file and pass its path after the repo: `reset-vault.sh -i 0 /mnt/c/path/to/repo /mnt/c/path/to/data.json`. A file avoids passing JSON through `wsl`'s command line, which would mangle the quotes.
3. **Launch** it, hidden. Running it again restarts Obsidian.
   ```powershell
   wsl -d Ubuntu -- bash <wsl-skill>/scripts/launch.sh -i 0
   ```
4. **Smoke check.** This accepts the "trust author" prompt, waits for plugins to load, and reports each plugin's version and command count, plus any modal it closed:
   ```powershell
   node <win-skill>\scripts\cdp.mjs -i 0 eval <win-skill>\scripts\examples\smoke.js
   ```
5. **Drive it.** Write a check file in your scratchpad and run `node <win-skill>\scripts\cdp.mjs -i 0 eval <file.js>`, or pass short code with `eval -e "<code>"`. The code runs in the Obsidian renderer with `app`, `activeDocument` and `require('electron')` in scope. It may `await` and should `return` a JSON-serialisable value, which is printed. Typical moves: `app.commands.executeCommandById('<plugin-id>:<command>')`, finding and filling modals through `activeDocument`, reading state from `app.plugins.plugins['<plugin-id>']`, creating notes with `app.vault.create()`. Each call times out after 60 seconds; pass `--timeout <seconds>` before `eval` for longer checks.
6. **Screenshot:** `node <win-skill>\scripts\cdp.mjs -i 0 shot <scratchpad>\shot.png`, then Read the PNG to look at it. Screenshots are the best way to confirm UI changes, so take one whenever the change is visual.
7. **Mobile layout:** `cdp.mjs -i 0 eval <win-skill>\scripts\examples\mobile-width.js`, then `shot`. It sets the real window to 390×844 and calls `app.emulateMobile(true)`. Undo with `app.emulateMobile(false)` and `require('electron').remote.getCurrentWindow().setSize(1600, 1000)`.
8. **New build:** stop, rebuild, reset and launch again. Reset won't run while the instance is up.
9. **Stop** when done: `wsl -d Ubuntu -- bash <wsl-skill>/scripts/stop.sh -i 0`. For an instance other than 0, also delete its root afterwards (`wsl -d Ubuntu -- rm -rf obsidian-test-N`, run from the WSL home folder with `--cd ~`) so `status.sh` stays tidy.

For raw protocol calls there is also `cdp.mjs -i 0 cdp <Method> [jsonParams]`.

`reset-vault.sh` deletes the instance root only when it is new, empty or holds the throwaway marker. It refuses `/`, the home folder, anything containing it, Windows drives, and plugin IDs that could escape the plugins folder. If it refuses, ask the user rather than deleting the folder yourself.

## Gotchas

- **`wsl -- <command>` runs its arguments through a shell inside WSL,** so `|`, `;`, `$` and `&` in them are interpreted there even when PowerShell quoted them. `wsl -d Ubuntu -- pgrep -af 'Xvfb|obsidian'` pipes into a bare `obsidian`, which starts an unhidden Obsidian with the default profile. Use `status.sh` to see what's running, check one name per call, and put anything more complex in a script file. For the same reason `pkill -f <pattern>` run through `wsl` can match its own wrapper shell and exit before killing anything; use `stop.sh`, or kill by PID.
- **Trust prompt on first open.** Community plugins stay off until **Trust author and enable plugins** is clicked. `smoke.js` clicks it.
- **No accounts or API keys.** The profile is fresh, so anything that calls a remote API fails until it has a key. Enter one in the hidden instance's settings only if the user gives you one for testing. Reset wipes it.
- **Settings opens in its own window (Obsidian 1.15+).** That window can become `activeDocument`, so modals may render there. `cdp.mjs` attaches to the main window, so use `activeDocument`, or close Settings first.
- **CDP `Emulation.*` overrides reset when the socket closes,** and every `cdp.mjs` call opens its own socket. Resize the real window with `setSize()` instead.
- **`app.emulateMobile()` reloads the window** and kills the running evaluation ("Inspected target navigated or closed"). Schedule it with `setTimeout` after returning, as `mobile-width.js` does. The next `cdp.mjs` call waits for the reload.
- **Plugin commands register a moment after `app.plugins.plugins[id]` appears.** Wait briefly before asserting on commands.
- **Logs** are in the instance root inside WSL: `obsidian.log` and `xvfb.log`. Read them when launch fails.
- **A `Refusing:` exit (code 2) from `cdp.mjs`** means the port belongs to an Obsidian whose vault lacks the marker. Stop and check what is on that port; never "fix" it by editing the guard.
- **Expert overrides.** `OBS_TEST_ROOT`, `OBS_TEST_DISPLAY` and `CDP_PORT` override what `-i` picks, but only for the command they're set on. Prefer `-i`.
