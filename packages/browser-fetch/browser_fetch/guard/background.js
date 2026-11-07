// Holds every top-level document request to WebFetch's redirect policy before
// it is sent, and keeps pages off this machine and private networks.
// session.py answers the policy; config.js names its port and token.
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

function ipv4(host) {
	const parts = host.split(".").map(Number);
	return parts.length === 4 &&
		parts.every((n) => Number.isInteger(n) && n >= 0 && n <= 255)
		? parts
		: null;
}

function isLocal(hostname) {
	const host = hostname.toLowerCase().replace(/\.$/, "");
	if (host === "localhost" || host.endsWith(".localhost")) return true;
	if (host.startsWith("[")) {
		const v6 = host.slice(1, -1);
		if (
			v6 === "::1" ||
			v6 === "::" ||
			/^f[cd]/.test(v6) ||
			/^fe[89ab]/.test(v6)
		)
			return true;
		// The URL parser writes a mapped IPv4 address in hex: ::ffff:7f00:1.
		const mapped = /^::ffff:([0-9a-f]{1,4}):([0-9a-f]{1,4})$/.exec(v6);
		if (!mapped) return false;
		const [high, low] = [parseInt(mapped[1], 16), parseInt(mapped[2], 16)];
		return isLocal(`${high >> 8}.${high & 255}.${low >> 8}.${low & 255}`);
	}
	const a = ipv4(host);
	if (!a) return false;
	return (
		a[0] === 0 ||
		a[0] === 10 ||
		a[0] === 127 ||
		a[0] >= 224 ||
		(a[0] === 100 && a[1] >= 64 && a[1] <= 127) ||
		(a[0] === 169 && a[1] === 254) ||
		(a[0] === 172 && a[1] >= 16 && a[1] <= 31) ||
		(a[0] === 192 && a[1] === 168) ||
		(a[0] === 198 && (a[1] === 18 || a[1] === 19))
	);
}

browser.webRequest.onBeforeRequest.addListener(
	async (details) => {
		if ((details.originUrl || "").startsWith("moz-extension:")) return {};
		if (details.type === "main_frame") {
			return (await allowed(
				"navigate",
				details.originUrl || "",
				details.url,
				0,
			))
				? {}
				: { cancel: true };
		}
		return isLocal(new URL(details.url).hostname) ? { cancel: true } : {};
	},
	{ urls: ["<all_urls>"] },
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
