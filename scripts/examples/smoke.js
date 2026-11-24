// Generic first check after launch:
//   node <skill>/scripts/cdp.mjs [-i N] eval <skill>/scripts/examples/smoke.js
//
// The file body runs inside an async function in the Obsidian renderer, so it can
// `await` and must `return` a JSON-serialisable value.
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// A fresh vault opens with "Do you trust the author of this vault?"; community
// plugins stay off until it is accepted. Accept it if it is showing.
const trust = [...activeDocument.querySelectorAll('.modal button')].find((button) =>
	button.innerText.startsWith('Trust author'),
);
if (trust) trust.click();

// Wait until every enabled plugin has loaded.
const enabled = () => [...app.plugins.enabledPlugins];
const allLoaded = () => enabled().length > 0 && enabled().every((id) => app.plugins.plugins[id]);
for (let i = 0; i < 50 && !allLoaded(); i++) await sleep(200);
await sleep(500); // let onload() finish registering commands
// Close any modal still open (e.g. a plugin's welcome dialog) so later checks start
// from a clean workspace, but report what was closed: it may be what you're testing.
const closedModals = [...activeDocument.querySelectorAll('.modal-container')].map((container) => {
	const title = container.querySelector('.modal-title')?.innerText || container.innerText.slice(0, 60);
	container.querySelector('.modal-close-button')?.click();
	return title;
});

return {
	vault: app.vault.getName(),
	trustedNow: Boolean(trust),
	closedModals,
	isMobile: app.isMobile,
	plugins: enabled().map((id) => ({
		id,
		loaded: Boolean(app.plugins.plugins[id]),
		version: app.plugins.plugins[id]?.manifest.version,
		commands: Object.keys(app.commands.commands).filter((c) => c.startsWith(id + ':')).length,
	})),
};
