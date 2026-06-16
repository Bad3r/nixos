const { app, BrowserWindow, shell } = require("electron");

const raindropHost = "raindrop.io";
const externalProtocols = new Set(["http:", "https:", "mailto:", "tel:"]);

// Hosts kept inside the app window (not the external browser) so social
// sign-in finishes in the Electron --user-data-dir profile. Exact hosts
// only: a whole-domain match would also trap normal bookmark links.
const oauthHosts = new Set([
	"accounts.google.com",
	"appleid.apple.com",
	"www.facebook.com",
	"m.facebook.com",
	"facebook.com",
	"api.twitter.com",
	"twitter.com",
	"x.com",
]);

function parseUrl(rawUrl) {
	try {
		return new URL(rawUrl);
	} catch (error) {
		console.error("Blocked invalid URL " + rawUrl + ": " + error.message);
		return null;
	}
}

function isRaindropUrl(rawUrl) {
	const url = parseUrl(rawUrl);
	if (url === null) {
		return false;
	}

	return (
		(url.protocol === "http:" || url.protocol === "https:") &&
		(url.hostname === raindropHost ||
			url.hostname.endsWith("." + raindropHost) ||
			oauthHosts.has(url.hostname))
	);
}

function openExternal(rawUrl) {
	const url = parseUrl(rawUrl);
	if (url === null) {
		return;
	}

	if (!externalProtocols.has(url.protocol)) {
		console.error("Blocked unsupported external URL scheme: " + url.protocol);
		return;
	}

	shell.openExternal(url.href).catch((error) => {
		console.error(
			"Failed to open external URL " + url.href + ": " + error.message,
		);
	});
}

function createWindow() {
	const window = new BrowserWindow({
		width: 1280,
		height: 900,
		title: "Raindrop.io",
		autoHideMenuBar: true,
		webPreferences: {
			contextIsolation: true,
			nodeIntegration: false,
			sandbox: true,
		},
	});

	window.webContents.setWindowOpenHandler(({ url }) => {
		if (isRaindropUrl(url)) {
			window.loadURL(url);
		} else {
			openExternal(url);
		}

		return { action: "deny" };
	});

	window.webContents.on("will-navigate", (event, url) => {
		if (isRaindropUrl(url)) {
			return;
		}

		event.preventDefault();
		openExternal(url);
	});

	window.loadURL("https://app.raindrop.io");
}

app.whenReady().then(() => {
	createWindow();

	app.on("activate", () => {
		if (BrowserWindow.getAllWindows().length === 0) {
			createWindow();
		}
	});
});

app.on("window-all-closed", () => {
	if (process.platform !== "darwin") {
		app.quit();
	}
});
