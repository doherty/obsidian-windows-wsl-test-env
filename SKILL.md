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

This installs Xvfb, jq and the latest official Obsidian `.deb`, whose declared dependencies supply its runtime libraries. Pass a version to pin one (tested with 1.15.1 on Ubuntu 26.04). If the final `ldd` check reports missing libraries, the package failed to declare them (an upstream bug; 1.15.1 omits `libgbm1` and `libasound2t64`). Install them with apt and run it again.

## Each test session

1. **Build the plugin** in the repo or worktree under test. The build must leave `main.js` and `manifest.json` in the repo root, plus `styles.css` if the plugin has one.
2. **Reset** the throwaway vault and install the build into it. Run this from the repo folder: `wsl` keeps the current folder, and the script defaults to it.
   ```powershell
   wsl -d Ubuntu -- bash <wsl-skill>/scripts/reset-vault.sh
   ```
   Or pass the repo as a `/mnt/c/...` path. To seed the plugin's settings (`data.json`), set `$env:OBS_TEST_PLUGIN_DATA='{"debugMode":true}'` and `$env:WSLENV='OBS_TEST_PLUGIN_DATA/u'` first.
3. **Launch** it, hidden. Running it again restarts Obsidian. To pick up a new build, rebuild and reset first.
   ```powershell
   wsl -d Ubuntu -- bash <wsl-skill>/scripts/launch.sh
   ```
4. **Smoke check.** This accepts the "trust author" prompt, waits for plugins to load and reports each plugin's version and command count:
   ```powershell
   node <win-skill>\scripts\cdp.mjs eval <win-skill>\scripts\examples\smoke.js
   ```
5. **Drive it.** Write a check file in your scratchpad and run `node <win-skill>\scripts\cdp.mjs eval <file.js>`, or pass short code with `eval -e "<code>"`. The code runs in the Obsidian renderer with `app`, `activeDocument` and `require('electron')` in scope. It may `await` and should `return` a JSON-serialisable value, which is printed. Typical moves: `app.commands.executeCommandById('<plugin-id>:<command>')`, finding and filling modals through `activeDocument`, reading state from `app.plugins.plugins['<plugin-id>']`, creating notes with `app.vault.create()`.
6. **Screenshot:** `node <win-skill>\scripts\cdp.mjs shot <scratchpad>\shot.png`, then Read the PNG to look at it. Screenshots are the best way to confirm UI changes, so take one whenever the change is visual.
7. **Mobile layout:** `cdp.mjs eval <win-skill>\scripts\examples\mobile-width.js`, then `shot`. It sets the real window to 390×844 and calls `app.emulateMobile(true)`. Undo with `app.emulateMobile(false)` and `require('electron').remote.getCurrentWindow().setSize(1600, 1000)`.
8. **Stop** when done: `wsl -d Ubuntu -- bash <wsl-skill>/scripts/stop.sh`.

For raw protocol calls there is also `cdp.mjs cdp <Method> [jsonParams]`.

## Settings and parallel instances

`env.sh` reads three settings from the environment: `OBS_TEST_ROOT` (default `~/obsidian-test` in WSL), `OBS_TEST_DISPLAY` (`:99`) and `CDP_PORT` (`9222`). Pass them from PowerShell through `WSLENV` with the `/u` flag.

If an instance is already running for another session (`wsl -d Ubuntu -- pgrep -af Xvfb` shows one), don't reset or stop it. Start a second one with all three changed:

```powershell
$env:OBS_TEST_ROOT='/home/<wsl-user>/obsidian-test-2'; $env:OBS_TEST_DISPLAY=':98'; $env:CDP_PORT='9223'; $env:WSLENV='OBS_TEST_ROOT/u:OBS_TEST_DISPLAY/u:CDP_PORT/u'
```

`cdp.mjs` reads `CDP_PORT` directly. Delete that extra root (`rm -rf` inside WSL) after stopping it.

`reset-vault.sh` deletes `OBS_TEST_ROOT` only when it is new, empty or holds the throwaway marker. It refuses `/`, the home folder, anything containing it, and Windows-drive paths. If it refuses, ask the user rather than deleting the folder yourself.

## Gotchas

- **`wsl -- <command>` runs its arguments through a shell inside WSL,** so `|`, `;`, `$` and `&` in them are interpreted there even when PowerShell quoted them. `wsl -d Ubuntu -- pgrep -af 'Xvfb|obsidian'` pipes into a bare `obsidian`, which starts an unhidden Obsidian with the default profile. Check one name per call (`pgrep -af Xvfb`, then `pgrep -af obsidian`), and put anything more complex in a script file. For the same reason `pkill -f <pattern>` run through `wsl` can match its own wrapper shell and exit before killing anything; use `stop.sh`, or kill by PID.
- **Trust prompt on first open.** Community plugins stay off until **Trust author and enable plugins** is clicked. `smoke.js` clicks it.
- **No accounts or API keys.** The profile is fresh, so anything that calls a remote API fails until it has a key. Enter one in the hidden instance's settings only if the user gives you one for testing. Reset wipes it.
- **Settings opens in its own window (Obsidian 1.15+).** That window can become `activeDocument`, so modals may render there. `cdp.mjs` attaches to the main window, so use `activeDocument`, or close Settings first.
- **CDP `Emulation.*` overrides reset when the socket closes,** and every `cdp.mjs` call opens its own socket. Resize the real window with `setSize()` instead.
- **`app.emulateMobile()` reloads the window** and kills the running evaluation ("Inspected target navigated or closed"). Schedule it with `setTimeout` after returning, as `mobile-width.js` does. The next `cdp.mjs` call waits for the reload.
- **Plugin commands register a moment after `app.plugins.plugins[id]` appears.** Wait briefly before asserting on commands.
- **Logs** are in `OBS_TEST_ROOT` inside WSL: `obsidian.log` and `xvfb.log`. Read them when launch fails.
- **A `Refusing:` exit (code 2) from `cdp.mjs`** means the port belongs to an Obsidian whose vault lacks the marker. Stop and check what is on that port; never "fix" it by editing the guard.
