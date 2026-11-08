// Holds every top-level document request to WebFetch's redirect policy before
// it is sent.
// session.py answers the policy; config.js names its port and token. The
// session navigates only after the "ready" this sends once both listeners
// are in place.
"use strict";

const { port, token } = globalThis.BROWSER_FETCH;
const policy = `http://127.0.0.1:${port}/check`;

async function allowed(kind, from, to, status) {
	try {
		const response = await fetch(policy, {
			method: "POST",
			headers: { "X-Token": token },
			body: JSON.stringify({ kind, from, to, status }),
		});
		return (await response.json()).allow === true;
	} catch {
		return false;
	}
}

browser.webRequest.onBeforeRequest.addListener(
	async (details) =>
		(await allowed("navigate", details.originUrl || "", details.url, 0))
			? {}
			: { cancel: true },
	{ urls: ["<all_urls>"], types: ["main_frame"] },
	["blocking"],
);

browser.webRequest.onHeadersReceived.addListener(
	async (details) => {
		if (details.statusCode < 300 || details.statusCode > 399) return {};
		const header = (details.responseHeaders || []).find(
			(h) => h.name.toLowerCase() === "location",
		);
		if (!header) return {};
		let target;
		try {
			target = new URL(header.value, details.url).href;
		} catch {
			return {};
		}
		return (await allowed("redirect", details.url, target, details.statusCode))
			? {}
			: { cancel: true };
	},
	{ urls: ["<all_urls>"], types: ["main_frame"] },
	["blocking", "responseHeaders"],
);

allowed("ready", "", "", 0);
