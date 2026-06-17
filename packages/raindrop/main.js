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

function isHttpUrl(url) {
	return url.protocol === "http:" || url.protocol === "https:";
}

function hasRaindropHost(url) {
	return (
		url.hostname === raindropHost || url.hostname.endsWith("." + raindropHost)
	);
}

function isRaindropUrl(rawUrl) {
	const url = parseUrl(rawUrl);
	if (url === null) {
		return false;
	}

	return isHttpUrl(url) && hasRaindropHost(url);
}

function isInAppUrl(rawUrl) {
	const url = parseUrl(rawUrl);
	if (url === null) {
		return false;
	}

	return (
		isHttpUrl(url) && (hasRaindropHost(url) || oauthHosts.has(url.hostname))
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

function childWindowOptions() {
	return {
		autoHideMenuBar: true,
		webPreferences: {
			contextIsolation: true,
			nodeIntegration: false,
			sandbox: true,
		},
	};
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

	configureWindow(window);
	window.loadURL("https://app.raindrop.io");
}

function configureWindow(window) {
	window.webContents.setWindowOpenHandler(({ url }) => {
		if (isInAppUrl(url)) {
			return {
				action: "allow",
				overrideBrowserWindowOptions: childWindowOptions(),
			};
		}

		openExternal(url);
		return { action: "deny" };
	});

	window.webContents.on("did-create-window", (childWindow) => {
		configureWindow(childWindow);
	});

	window.webContents.on("will-navigate", (event, url) => {
		if (isInAppUrl(url)) {
			return;
		}

		event.preventDefault();
		openExternal(url);
	});

	window.webContents.on("will-redirect", (event, url) => {
		if (!isRaindropUrl(window.webContents.getURL()) || isInAppUrl(url)) {
			return;
		}

		event.preventDefault();
		openExternal(url);
	});
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
