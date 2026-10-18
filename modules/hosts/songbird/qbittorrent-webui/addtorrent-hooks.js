// Loaded by the stock addtorrent.html through the script tag that
// qbittorrent-webui.nix adds. Gives the add dialog the desktop client's
// duplicate prompt (GUIAddTorrentManager::processTorrent); the stock dialog
// closes silently when the server rejects a duplicate.
"use strict";

(() => {
	const params = new URLSearchParams(location.search);
	const windowId = params.get("windowId");
	const source = params.get("source") ?? "";
	// A shared dialog adds several torrents and never loads metadata.
	if (windowId === null || params.get("shared") === "true") return;

	const windowEl = () => window.parent.document.getElementById(windowId);
	const markWindow = (attribute) => windowEl()?.setAttribute(attribute, "");

	const checkDuplicate = async (metadata) => {
		// Set before the first await so the 3 s fallback in index-hooks.js cannot
		// reveal the window mid-check; the fetch timeout bounds how long it stays
		// hidden.
		markWindow("data-checking");
		const hashes = [metadata.infohash_v1, metadata.infohash_v2].filter(
			(hash) => hash,
		);
		let existing;
		try {
			// hashes matches TorrentID, which for a v2-only torrent is the
			// v2 infohash truncated to 40 hex chars.
			const response = await fetch(
				"api/v2/torrents/info?hashes=" +
					[...hashes, ...hashes.map((hash) => hash.slice(0, 40))].join("|"),
				{ cache: "no-store", signal: AbortSignal.timeout(5000) },
			);
			if (!response.ok)
				throw new Error("torrents/info answered " + response.status);
			existing = (await response.json()).find(
				(torrent) =>
					hashes.includes(torrent.infohash_v1) ||
					hashes.includes(torrent.infohash_v2),
			);
		} catch (error) {
			console.error("Duplicate torrent check failed:", error);
			markWindow("data-checked");
			return;
		}
		if (existing === undefined) {
			markWindow("data-checked");
			return;
		}

		markWindow("data-duplicate");
		// A duplicate magnet's metadata is the existing torrent's, so its
		// trackers come from the link.
		const isMagnet = source.startsWith("magnet:");
		let trackers;
		let webseeds;
		if (isMagnet) {
			const link = [...new URL(source).searchParams];
			trackers = link
				.filter(([key]) => /^tr(\.\d+)?$/.test(key))
				.map(([, value]) => value);
			webseeds = link.filter(([key]) => key === "ws").map(([, value]) => value);
		} else {
			// addTrackers starts the next tier at each blank line.
			trackers = [...(metadata.trackers ?? [])]
				.sort((a, b) => a.tier - b.tier)
				.flatMap((tracker, i, all) =>
					i > 0 && tracker.tier !== all[i - 1].tier
						? ["", tracker.url]
						: [tracker.url],
				);
			webseeds = metadata.webseeds ?? [];
		}

		const message =
			"Torrent '" + existing.name + "' is already in the transfer list. ";
		if (
			existing.private === true ||
			(!isMagnet && metadata.info?.private === true)
		) {
			alert(
				message + "Trackers cannot be merged because it is a private torrent.",
			);
		} else if (
			confirm(message + "Do you want to merge trackers from new source?")
		) {
			try {
				for (const [endpoint, urls] of [
					["api/v2/torrents/addTrackers", trackers.join("\n")],
					["api/v2/torrents/addWebSeeds", webseeds.join("|")],
				]) {
					if (urls.length === 0) continue;
					const response = await fetch(endpoint, {
						method: "POST",
						body: new URLSearchParams({ hash: existing.hash, urls: urls }),
					});
					if (!response.ok)
						throw new Error(
							endpoint +
								" answered " +
								response.status +
								": " +
								(await response.text()),
						);
				}
			} catch (error) {
				alert("Could not merge trackers: " + error.message);
			}
		}
		window.parent.qBittorrent.Client.closeFrameWindow(window);
	};

	let duplicateCheck = null;
	const onMetadata = (metadata) => {
		if (
			duplicateCheck !== null ||
			!(metadata?.infohash_v1 || metadata?.infohash_v2)
		)
			return;
		duplicateCheck = checkDuplicate(metadata).catch((error) => {
			console.error(
				"Duplicate check crashed; showing the stock dialog:",
				error,
			);
			windowEl()?.removeAttribute("data-duplicate");
			markWindow("data-checked");
		});
	};

	// The stock dialog gets metadata two ways: its own fetchMetadata polling for
	// a link, and a message from the main window for an uploaded file.
	const stockFetch = window.fetch;
	window.fetch = (...args) => {
		const response = stockFetch.apply(window, args);
		const url = args[0] instanceof Request ? args[0].url : String(args[0]);
		if (
			new URL(url, location.href).pathname.endsWith(
				"/api/v2/torrents/fetchMetadata",
			)
		) {
			response
				.then((r) => (r.ok ? r.clone().json() : undefined))
				.then((metadata) => {
					if (metadata !== undefined) onMetadata(metadata);
				})
				.catch((error) =>
					console.warn(
						"addtorrent-hooks.js: no duplicate check from this fetchMetadata:",
						error,
					),
				);
		}
		return response;
	};
	window.addEventListener("message", (event) => {
		if (
			event.origin === window.origin &&
			event.data?.type === "addtorrent_metadata"
		)
			onMetadata(event.data.metadata);
	});
})();
