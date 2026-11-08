# Copyright (c) 2026 Bad3r
"""Check the installed browser's policies and profile preservation across a restart."""

import argparse
import json
import os
import socket
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Any

STATE = """
return (async () => {
  const {AddonManager} = ChromeUtils.importESModule("resource://gre/modules/AddonManager.sys.mjs");
  const {SearchService} = ChromeUtils.importESModule("moz-src:///toolkit/components/search/SearchService.sys.mjs");
  const {PlacesUtils} = ChromeUtils.importESModule("resource://gre/modules/PlacesUtils.sys.mjs");
  await SearchService.init();
  const engines = await SearchService.getEngines();
  const addons = await AddonManager.getAllAddons();
  return {
    searchReady: SearchService.hasSuccessfullyInitialized,
    engines: engines.map(e => ({name: e.name, url: e.getSubmission("probe").uri.spec})),
    defaultEngine: (await SearchService.getDefault()).name,
    addons: addons.map(a => ({id: a.id, active: a.isActive})),
    policies: Services.policies.getActivePolicies(),
    cookie: Services.cookies.cookies.find(
      c => c.host === "packaging.example" && c.name === "preserved")?.value,
    bookmark: (await PlacesUtils.bookmarks.fetch({url: "https://packaging.example/preserved"}))?.title,
    preference: Services.prefs.getStringPref("camoufox.packaging.preserved", ""),
  };
})();
"""

SEED = """
return (async () => {
  const {PlacesUtils} = ChromeUtils.importESModule("resource://gre/modules/PlacesUtils.sys.mjs");
  Services.cookies.add("packaging.example", "/", "preserved", "cookie-fixture",
    true, true, false, Date.now() + 3600000, {},
    Ci.nsICookie.SAMESITE_LAX, Ci.nsICookie.SCHEME_HTTPS);
  await PlacesUtils.bookmarks.insert({parentGuid: PlacesUtils.bookmarks.unfiledGuid,
    url: "https://packaging.example/preserved", title: "bookmark-fixture"});
  Services.prefs.setStringPref("camoufox.packaging.preserved", "preference-fixture");
  return true;
})();
"""

TARGETS = {
    "webcompat@mozilla.org",
    "pictureinpicture@mozilla.org",
    "formautofill@mozilla.org",
}


def require(condition: bool, message: str) -> None:  # noqa: FBT001
    """Fail with the observed contract violation."""
    if not condition:
        raise RuntimeError(message)


class Browser:
    """A disposable headless browser and its privileged Marionette connection."""

    def __init__(self, executable: str, root: Path, name: str) -> None:
        """Start on the fixture profile, leaving the user's environment untouched."""
        with socket.socket() as reservation:
            reservation.bind(("127.0.0.1", 0))
            port = reservation.getsockname()[1]
        profile = root / "profile"
        profile.mkdir(exist_ok=True)
        (profile / "user.js").write_text(f'user_pref("marionette.port", {port});\n')
        self.log_path = root / f"{name}.log"
        self.sequence = 0
        with self.log_path.open("w") as log:
            self.process = subprocess.Popen(
                [
                    executable,
                    "--headless",
                    "--no-remote",
                    "--profile",
                    str(profile),
                    "--marionette",
                    "--remote-allow-system-access",
                    "about:blank",
                ],
                env={**os.environ, "HOME": str(root), "XDG_CACHE_HOME": str(root / "cache")},
                stdout=log,
                stderr=subprocess.STDOUT,
            )
        try:
            until = time.monotonic() + 30
            while True:
                try:
                    self.sock = socket.create_connection(("127.0.0.1", port), timeout=1)
                    break
                except OSError:
                    if self.process.poll() is not None or time.monotonic() >= until:
                        raise
                    time.sleep(0.1)
            self.sock.settimeout(30)
            self.receive()
            self.call("WebDriver:NewSession", {"capabilities": {}})
            self.call("Marionette:SetContext", {"value": "chrome"})
        except BaseException:
            self.stop()
            raise

    def receive(self) -> Any:  # noqa: ANN401
        """Read one length-prefixed JSON message."""
        header = bytearray()
        while not header.endswith(b":"):
            chunk = self.sock.recv(1)
            if not chunk:
                msg = "Marionette closed the connection"
                raise ConnectionError(msg)
            header.extend(chunk)
        size = int(header[:-1])
        body = bytearray()
        while len(body) < size:
            chunk = self.sock.recv(size - len(body))
            if not chunk:
                msg = "Marionette closed the connection within a message"
                raise ConnectionError(msg)
            body.extend(chunk)
        return json.loads(body)

    def call(self, command: str, parameters: dict[str, Any]) -> Any:  # noqa: ANN401
        """Issue a command and surface protocol errors."""
        self.sequence += 1
        payload = json.dumps([0, self.sequence, command, parameters]).encode()
        self.sock.sendall(str(len(payload)).encode() + b":" + payload)
        reply = self.receive()
        require(reply[:2] == [1, self.sequence], f"Unexpected Marionette reply: {reply}")
        require(reply[2] is None, f"{command}: {reply[2]}")
        return reply[3]

    def js(self, script: str) -> Any:  # noqa: ANN401
        """Evaluate an awaited script in the browser's privileged context."""
        return self.call("WebDriver:ExecuteScript", {"script": script, "args": []})["value"]

    def stop(self) -> None:
        """Reap only this fixture's browser, including on a failed check."""
        if hasattr(self, "sock"):
            self.sock.close()
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait()
        print(self.log_path.read_text())

    def quit(self) -> None:
        """Close normally so the next launch checks saved data."""
        self.call("Marionette:Quit", {"flags": ["eAttemptQuit"]})
        require(self.process.wait(timeout=30) == 0, "The fixture browser did not close cleanly")


def check(state: dict[str, Any]) -> None:
    """Require effective removal, a working inert search engine and retained policies."""
    require(state["searchReady"], "The search service did not initialize")
    require(
        state["engines"] == [{"name": "None", "url": "http://127.0.0.1/?q=probe"}]
        and state["defaultEngine"] == "None",
        f"Unexpected search state: {state['engines']}",
    )
    ids = {addon["id"] for addon in state["addons"]}
    require(not ids & TARGETS, f"Unwanted built-ins remain registered: {ids & TARGETS}")
    policies = state["policies"]
    for name in (
        "DisableAppUpdate",
        "DisableTelemetry",
        "DisableFirefoxStudies",
        "DisableSystemAddonUpdate",
    ):
        require(policies.get(name) is True, f"Policy {name} is missing")
    require(policies["ExtensionUpdate"] is False, "Extension updates are allowed")
    require(
        policies["3rdparty"]["Extensions"]["uBlock0@raymondhill.net"]["userSettings"]
        == [["autoUpdate", "false"]],
        "The uBlock Origin filter-update policy changed",
    )


def main() -> None:
    """Check a fresh profile, a restart, and optionally an older package's profile."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable")
    parser.add_argument("--seed-binary")
    args = parser.parse_args()
    retained_addons: set[str] = set()
    with tempfile.TemporaryDirectory(prefix="camoufox-policies-") as temporary:
        root = Path(temporary)
        for name, executable in (
            ("first", args.seed_binary or args.executable),
            ("restart", args.executable),
        ):
            browser = Browser(executable, root, name)
            try:
                state = browser.js(STATE)
                print(name, json.dumps(state, sort_keys=True))
                if name == "first":
                    retained_addons = {a["id"] for a in state["addons"]} - TARGETS
                    if args.seed_binary:
                        active = {a["id"] for a in state["addons"] if a["active"]}
                        require(
                            active >= TARGETS, "The seed did not reproduce the active built-ins"
                        )
                    else:
                        check(state)
                    browser.js(SEED)
                else:
                    check(state)
                    require(
                        {a["id"] for a in state["addons"]} >= retained_addons,
                        "An unrelated add-on was removed",
                    )
                    for key in ("cookie", "bookmark", "preference"):
                        require(state.get(key) == f"{key}-fixture", f"The saved {key} was lost")
                browser.quit()
            finally:
                browser.stop()
            if name != "first" or not args.seed_binary:
                log = browser.log_path.read_text()
                for failure in (
                    "An engine called None already exists",
                    "couldn't be uninstalled",
                    "failure initializing search",
                ):
                    require(failure not in log, f"The browser logged: {failure}")
    print("PASS: policies, inert search, built-in removal and saved profile data")


if __name__ == "__main__":
    main()
