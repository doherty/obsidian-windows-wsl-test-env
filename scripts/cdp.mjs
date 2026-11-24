#!/usr/bin/env node
// Minimal Chrome DevTools Protocol client for the hidden test Obsidian started by
// launch.sh. Runs from Windows or WSL with Node 22+ (needs the global WebSocket
// and fetch).
//
//   node cdp.mjs [-i N] [--timeout S] eval <file.js>      evaluate a file's body (await allowed, `return` a value)
//   node cdp.mjs [-i N] [--timeout S] eval -e "<code>"    evaluate inline code
//   node cdp.mjs [-i N] [--timeout S] shot <out.png>      screenshot the main window
//   node cdp.mjs [-i N] [--timeout S] cdp <Method> [json] raw protocol call
//
// -i N picks the instance (port 9222+N, default 0), matching the shell scripts.
// The CDP_PORT environment variable overrides it. --timeout (default 60 seconds)
// bounds each protocol call, so code that never settles fails instead of hanging.
//
// The code runs inside the Obsidian renderer, so `app`, `activeDocument` and
// `require('electron')` are in scope. Results are printed as JSON.
//
// Safety guard: it refuses to do anything unless the connected vault contains the
// marker file written by reset-vault.sh and lives on the WSL filesystem. This keeps
// it from ever touching a real vault, even if the port belongs to another Obsidian.
import { readFileSync, writeFileSync } from 'node:fs';

// Must match OBS_TEST_MARKER in env.sh.
const MARKER = '.obsidian-throwaway-test-vault';
const USAGE =
	'Usage: cdp.mjs [-i N] [--timeout S] eval <file.js | -e code> | shot <out.png> | cdp <Method> [jsonParams]';

const args = process.argv.slice(2);
let instance = 0;
let timeoutMs = 60_000;
while (args[0] === '-i' || args[0] === '--timeout') {
	const [flag, value] = args.splice(0, 2);
	const number = Number(value);
	if (flag === '-i' && Number.isInteger(number) && number >= 0 && number <= 49) instance = number;
	else if (flag === '--timeout' && number > 0) timeoutMs = number * 1000;
	else {
		console.error(`Bad value for ${flag}: ${value}\n${USAGE}`);
		process.exit(1);
	}
}
const [mode, arg, arg2] = args;
if (!['eval', 'shot', 'cdp'].includes(mode) || !arg || (mode === 'eval' && arg === '-e' && !arg2)) {
	console.error(USAGE);
	process.exit(1);
}
const PORT = process.env.CDP_PORT ?? String(9222 + instance);

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// Find the main workspace window. Retries for a few seconds: WSL's forwarding of
// the port to Windows can lag behind launch.sh, and the window may be reloading.
// Pop-out windows (Settings in Obsidian 1.15+) show as about:blank targets and
// are skipped; reach them from the main window via `activeDocument` / `activeWindow`.
let page;
let lastProblem = '';
for (let attempt = 0; attempt < 20 && !page; attempt++) {
	if (attempt) await sleep(500);
	try {
		const targets = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();
		page = targets.find((t) => t.type === 'page' && t.url.startsWith('app://obsidian.md/index.html'));
		lastProblem = `no Obsidian window among the targets on port ${PORT}`;
	} catch (error) {
		lastProblem = `no DevTools endpoint on 127.0.0.1:${PORT} (${error.cause?.code ?? error.message}); is launch.sh -i ${instance} running?`;
	}
}
if (!page) {
	console.error(`Gave up: ${lastProblem}`);
	process.exit(1);
}

const ws = new WebSocket(page.webSocketDebuggerUrl);
await new Promise((resolve, reject) => {
	ws.onopen = resolve;
	ws.onerror = () => reject(new Error(`could not open ${page.webSocketDebuggerUrl}`));
}).catch((error) => {
	console.error(error.message);
	process.exit(1);
});
let nextId = 0;
const pending = new Map();
ws.onmessage = (event) => {
	const msg = JSON.parse(event.data);
	if (msg.id && pending.has(msg.id)) {
		pending.get(msg.id).resolve(msg);
		pending.delete(msg.id);
	}
};
ws.onclose = () => {
	for (const { reject } of pending.values()) reject(new Error('Obsidian closed the connection'));
	pending.clear();
};
const send = (method, params = {}) =>
	new Promise((resolve, reject) => {
		const id = ++nextId;
		const timer = setTimeout(() => {
			pending.delete(id);
			reject(new Error(`${method} timed out after ${timeoutMs / 1000} s (raise it with --timeout)`));
		}, timeoutMs);
		const settle = (fn) => (value) => {
			clearTimeout(timer);
			fn(value);
		};
		pending.set(id, { resolve: settle(resolve), reject: settle(reject) });
		ws.send(JSON.stringify({ id, method, params }));
	});

async function evaluate(expression) {
	const response = await send('Runtime.evaluate', {
		expression,
		awaitPromise: true,
		returnByValue: true,
		userGesture: true,
	});
	if (response.error) throw new Error(response.error.message);
	if (response.result?.exceptionDetails) {
		const details = response.result.exceptionDetails;
		throw new Error(details.exception?.description ?? details.text);
	}
	return response.result?.result?.value;
}

function fail(message, code = 1) {
	console.error(message);
	ws.close();
	process.exit(code);
}

// Guard: only ever act on the throwaway vault. Waits up to ~15 s for the window to
// finish (re)loading and the workspace layout to be ready, e.g. right after launch
// or app.emulateMobile().
let where;
try {
	where = await evaluate(`(async () => {
		const ready = () => globalThis.app?.vault?.adapter && globalThis.app?.workspace?.layoutReady;
		for (let i = 0; i < 75 && !ready(); i++) await new Promise((r) => setTimeout(r, 200));
		const adapter = globalThis.app?.vault?.adapter;
		if (!adapter) return null;
		return {
			name: app.vault.getName(),
			path: adapter.basePath ?? adapter.getBasePath?.(),
			marker: await adapter.exists(${JSON.stringify(MARKER)}),
		};
	})()`);
} catch (error) {
	fail(`Could not inspect the vault: ${error.message}`);
}
if (where === null) fail('Timed out waiting for Obsidian to open a vault; see obsidian.log in the instance root.');
const path = String(where?.path ?? '');
if (!where?.marker || !path.startsWith('/') || path.startsWith('/mnt/')) {
	fail(`Refusing: the connected vault is not the throwaway test vault: ${JSON.stringify(where)}`, 2);
}

try {
	if (mode === 'eval') {
		const code = arg === '-e' ? arg2 : readFileSync(arg, 'utf8');
		const value = await evaluate(`(async () => { ${code}\n})()`);
		console.log(value === undefined ? '(no value returned)' : JSON.stringify(value, null, 2));
	} else if (mode === 'shot') {
		const response = await send('Page.captureScreenshot', { format: 'png' });
		if (response.error) throw new Error(response.error.message);
		writeFileSync(arg, Buffer.from(response.result.data, 'base64'));
		console.log('saved', arg);
	} else {
		// Note: overrides such as Emulation.* last only while this socket is open.
		const response = await send(arg, arg2 ? JSON.parse(arg2) : {});
		if (response.error) {
			console.error(JSON.stringify(response.error));
			process.exitCode = 1;
		} else {
			console.log(JSON.stringify(response.result));
		}
	}
} catch (error) {
	console.error(error.message);
	process.exitCode = 1;
} finally {
	ws.close();
}
