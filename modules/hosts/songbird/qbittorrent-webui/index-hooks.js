// Loaded by the stock index.html through the script tag that
// qbittorrent-webui.nix adds. Every add window stays invisible until
// addtorrent-hooks.js clears its duplicate check, or for 3 s if no check
// starts. A #download= link from the qbittorrent-webui handler opens an add
// window per source instead of the stock Download from URLs dialog, and the
// tab closes once each of those windows has come and gone (added, cancelled,
// or a duplicate); browsers allow that for a tab with one history entry.
"use strict";

(() => {
	const client = window.qBittorrent?.Client;
	if (
		typeof client?.createAddTorrentWindow !== "function" ||
		!(client.categoryMap instanceof Map) ||
		!(client.tagMap instanceof Map)
	) {
		console.error(
			"index-hooks.js: window.qBittorrent.Client lacks createAddTorrentWindow, categoryMap, or tagMap; running the stock Web UI",
		);
		return;
	}

	// Opacity, not visibility: MochaUI sets visibility inline on the iframe,
	// and a visible child escapes a hidden parent.
	document.head.append(
		Object.assign(document.createElement("style"), {
			textContent:
				"div.mocha[id^=uploadPage-]:not([data-checked]), div.mocha[data-duplicate] { opacity: 0 !important; pointer-events: none !important; }",
		}),
	);
	const revealUnlessChecking = (windowEl) =>
		setTimeout(() => {
			if (
				!windowEl.hasAttribute("data-duplicate") &&
				!windowEl.hasAttribute("data-checking")
			)
				windowEl.setAttribute("data-checked", "");
		}, 3000);
	const observer = new MutationObserver((records) => {
		for (const record of records) {
			for (const node of record.addedNodes) {
				if (
					node instanceof Element &&
					node.matches("div.mocha[id^=uploadPage-]")
				)
					revealUnlessChecking(node);
			}
		}
	});
	// MochaUI adds windows to #desktop when the page has one, else to body.
	for (const container of [document.getElementById("desktop"), document.body]) {
		if (container !== null) observer.observe(container, { childList: true });
	}

	const downloadHash = "#download=";
	if (!location.hash.startsWith(downloadHash)) return;
	const sources = decodeURIComponent(
		location.hash.substring(downloadHash.length),
	)
		.split("\n")
		.map((source) => source.trim())
		.filter((source) => source.length > 0);
	// Deferred scripts run before the transfer list loads, so the stock
	// handleDownloadParam then finds no hash to open its dialog for.
	history.replaceState("", document.title, location.pathname + location.search);

	// The add dialog reads categoryMap and tagMap once, when it loads, so the
	// windows wait for the first sync/maindata response to fill both.
	const deadline = Date.now() + 30000;
	const stockFetch = window.fetch;
	const firstSync = new Promise((resolve) => {
		window.fetch = (...args) => {
			const response = stockFetch.apply(window, args);
			const url = args[0] instanceof Request ? args[0].url : String(args[0]);
			if (
				new URL(url, location.href).pathname.endsWith("/api/v2/sync/maindata")
			) {
				response
					.then((r) => (r.ok ? r.clone().json() : undefined))
					.then(
						(data) => {
							if (data === undefined) return;
							window.fetch = stockFetch;
							resolve(data);
						},
						(error) =>
							console.warn(
								"index-hooks.js: waiting for the next sync/maindata after:",
								error,
							),
					);
			}
			return response;
		};
	});
	const mapsFilled = (data) =>
		new Promise((resolve, reject) => {
			const categories = Object.keys(data.categories ?? {}).length;
			const tags = (data.tags ?? []).length;
			const poll = () => {
				if (client.categoryMap.size >= categories && client.tagMap.size >= tags)
					resolve();
				else if (Date.now() > deadline)
					reject(new Error("categoryMap and tagMap never filled"));
				else setTimeout(poll, 50);
			};
			setTimeout(poll, 0);
		});
	const timeout = new Promise((_, reject) =>
		setTimeout(
			() => reject(new Error("no sync/maindata response")),
			deadline - Date.now(),
		),
	);

	const pending = new Set(
		sources.map((source) => "uploadPage-" + encodeURIComponent(source)),
	);
	const seen = new Set();
	const closeWhenDone = () => {
		for (const id of pending) {
			if (document.getElementById(id) !== null) seen.add(id);
			else if (seen.has(id)) pending.delete(id);
		}
		if (pending.size > 0) setTimeout(closeWhenDone, 250);
		else window.close();
	};
	const openAddWindows = () => {
		for (const source of sources)
			client.createAddTorrentWindow(
				"QBT_TR(Magnet link)QBT_TR[CONTEXT=DownloadFromURLDialog]",
				source,
			);
		closeWhenDone();
	};
	Promise.race([firstSync.then(mapsFilled), timeout]).then(
		openAddWindows,
		(error) => {
			window.fetch = stockFetch;
			console.error(
				"index-hooks.js: opening the add windows without categories or tags:",
				error,
			);
			openAddWindows();
		},
	);
})();
