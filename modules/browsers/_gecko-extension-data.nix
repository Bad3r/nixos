/*
  Internal: pure Gecko extension identifiers and FirefoxPWA runtime policies.

  This helper is shared by Home Manager Gecko profile configuration and the
  NixOS-level firefoxpwa overlay. Keep it independent from module `config` and
  `pkgs` so package overlays can import it without depending on Home Manager
  evaluation state.
*/
{ lib }:
let
  # Use AMO's extension-ID URL form so the install URL matches the
  # ExtensionSettings policy key.
  amoLatestBaseUrl = "https://addons.mozilla.org/firefox/downloads/latest/";
  mkAmoInstallUrl =
    extension:
    "${amoLatestBaseUrl}${lib.replaceStrings [ "{" "}" ] [ "%7B" "%7D" ] extension}/latest.xpi";

  allowedWidgetChars = lib.stringToCharacters "abcdefghijklmnopqrstuvwxyz0123456789_-";
  toWidgetId =
    extension:
    let
      sanitizeChar = char: if builtins.elem char allowedWidgetChars then char else "_";
    in
    "${lib.stringAsChars sanitizeChar (lib.toLower extension)}-browser-action";

  ublockOrigin = "uBlock0@raymondhill.net";
  onePassword = "{d634138d-c276-4fc8-924b-40a0ea21d284}";

  arabicDictionary = "ar@dictionaries.addons.mozilla.org";
  cookieAutoDelete = "CookieAutoDelete@kennydo.com";
  darkreader = "addon@darkreader.org";
  foxyproxy = "foxyproxy@eric.h.jung";
  languageTool = "languagetool-webextension@languagetool.org";
  printEdit = "printedit-we@DW-dev";
  raindrop = "jid0-adyhmvsP91nUO8pRv0Mn2VKeB84@jetpack";
  savePage = "savepage-we@DW-dev";
  svgGobbler = "{7962ff4a-5985-4cf2-9777-4bb642ad05b8}";
  tabStash = "tab-stash@condordes.net";
  tridactyl = "tridactyl.vim@cmcaine.co.uk";
  violentmonkey = "{aecec67f-0d10-4fa7-b7c7-609a2db280cf}";
  wappalyzer = "wappalyzer@crunchlabz.com";
  webArchives = "{d07ccf11-c0cd-4938-a265-2a4d6ad01189}";

  # PWAsForFirefox management extension. Installed on the regular gecko browsers
  # so PWAs can be installed and managed from the browser, but user-disableable.
  # The native connector is wired in modules/browsers/{firefox,librewolf}/home.nix.
  firefoxpwaExt = "firefoxpwa@filips.si";

  # The extension ships only through AMO, whose download URL needs a per-version
  # opaque file id that cannot be derived from the version string. The pin is
  # generated from the nixpkgs connector version by
  # scripts/update-firefoxpwa-extension.py (refreshed on flake bumps by
  # update-flake.yml and on a schedule by update-firefoxpwa-extension.yml), so
  # the file id is never hand-maintained. The extension and connector only need a
  # shared major version to stay protocol-compatible (upstream checkNativeStatus
  # reports a differing minor/patch as compatible), and the generator pins the
  # newest published extension at or below the connector version. A stale pin
  # (package bumped before the generator reran) fails fast below instead of
  # silently installing a mismatched extension.
  firefoxpwaExtensionPin = builtins.fromJSON (builtins.readFile ./_firefoxpwa-extension-pin.json);
  mkFirefoxpwaInstallUrl =
    version:
    if firefoxpwaExtensionPin.packageVersion == version then
      firefoxpwaExtensionPin.url
    else
      throw "firefoxpwa management-extension pin is stale: pinned for connector ${firefoxpwaExtensionPin.packageVersion} but pkgs.firefoxpwa is ${version}. Refresh modules/browsers/_firefoxpwa-extension-pin.json with scripts/update-firefoxpwa-extension.py (or run the update-firefoxpwa-extension workflow).";

  # Tab Reloader (page auto refresh). Installed only into the firefoxpwa runtime
  # profiles via firefoxpwaRuntimePolicies (normal_installed, user-disableable),
  # never the regular browsers; periodic reloads keep authenticated PWA sessions
  # alive past idle timeouts.
  tabReloader = "jid0-bnmfwWw2w2w4e4edvcdDbnMhdVg@jetpack";

  policyExtensionIds = [
    arabicDictionary
    cookieAutoDelete
    darkreader
    foxyproxy
    languageTool
    onePassword
    printEdit
    raindrop
    savePage
    svgGobbler
    tabStash
    tridactyl
    ublockOrigin
    violentmonkey
    wappalyzer
    webArchives
  ];

  # Gecko disallows `uninstall-extension:<id>` for normal_installed just as it
  # does for force_installed, so about:addons keeps Remove greyed out; the only
  # permission normal_installed adds back is Disable. Dropping an add-on from
  # the policy set is the only way to make it truly removable.
  mkNormalInstalledPolicy = extension: {
    installation_mode = "normal_installed";
    install_url = mkAmoInstallUrl extension;
  };

  # Firefox grants private-window access to a non-privileged add-on only when
  # policy asks for it, so without this the ad blocker and the password manager
  # are silently inert in private windows. Setting the key at all also removes
  # the per-addon "Run in Private Windows" toggle from about:addons, so keep the
  # list to add-ons whose absence in a private window is itself the hazard.
  privateBrowsingExtensionIds = [
    onePassword
    ublockOrigin
  ];

  mkPrivateBrowsingPolicy =
    extension:
    mkNormalInstalledPolicy extension
    // {
      private_browsing = true;
    };

  # Enterprise policy applied to the firefoxpwa runtime (every PWA profile) by
  # modules/custom-overlays/firefoxpwa.nix. The declared add-ons are installed
  # as user-disableable defaults; 1Password reaches its desktop app through the
  # native-messaging host the firefox module already drops in
  # ~/.mozilla/native-messaging-hosts, which the runtime reads
  # (XRE_USER_NATIVE_MANIFESTS is the hardcoded legacy path).
  # uBlock here keeps default settings: the medium-mode extensionStorage below is
  # scoped to Home Manager profiles, and PWA profile ULIDs are generated at
  # runtime, so per-profile seeding is not reliable.
  firefoxpwaRuntimePolicies = {
    ExtensionSettings = {
      "${ublockOrigin}" = mkPrivateBrowsingPolicy ublockOrigin;
      "${onePassword}" = mkPrivateBrowsingPolicy onePassword;
      "${tridactyl}" = mkNormalInstalledPolicy tridactyl;
      "${tabReloader}" = mkNormalInstalledPolicy tabReloader;
    };
    DisableAppUpdate = true;
    DisableTelemetry = true;
    DisableFirefoxStudies = true;
  };
in
{
  inherit
    toWidgetId
    ublockOrigin
    onePassword
    cookieAutoDelete
    darkreader
    foxyproxy
    languageTool
    printEdit
    raindrop
    savePage
    svgGobbler
    tabStash
    tridactyl
    violentmonkey
    webArchives
    firefoxpwaExt
    mkFirefoxpwaInstallUrl
    policyExtensionIds
    privateBrowsingExtensionIds
    mkNormalInstalledPolicy
    mkPrivateBrowsingPolicy
    firefoxpwaRuntimePolicies
    ;
}
