/*
  Internal: shared Gecko-browser extensions
  Description: ExtensionSettings policy, per-profile extension package lists,
  and uBlock Origin storage settings shared between Firefox, Floorp, and LibreWolf.

  Summary:
    * Centralizes the AMO force-install entries (uBO, 1Password, SVG Gobbler)
      so every Gecko browser receives the same policy surface. Firefox's
      `policies.json` is browser-wide rather than per-profile, so every
      entry below is force-installed into `primary`, `work`, and
      `ephemeral` alike.
    * Splits the per-profile NUR extension package lists into primary /
      work / ephemeral. Profile assignment is the consumer's responsibility;
      these lists layer on top of the browser-wide ExtensionSettings policy.
    * Mirrors LibreWolf's uBlock Origin default filter-list selection so the
      three browsers ship identical blocking out of the box.
    * Stays underscore-prefixed so automatic module discovery does not import it.
*/

{ firefox-addons }:
let
  # AMO's `/latest/<slug>/latest.xpi` endpoint accepts a URL-safe slug and
  # redirects to the current signed XPI. The extension ID (`uBlock0@...`,
  # `{GUID}`) must be used as the ExtensionSettings policy key; slugs are
  # used only for the install URL so the path stays URL-safe.
  amoLatestBaseUrl = "https://addons.mozilla.org/firefox/downloads/latest/";

  ublockOriginId = "uBlock0@raymondhill.net";
  ublockOriginSlug = "ublock-origin";
  ublockOriginInstallUrl = "${amoLatestBaseUrl}${ublockOriginSlug}/latest.xpi";

  onePasswordId = "{d634138d-c276-4fc8-924b-40a0ea21d284}";
  onePasswordSlug = "1password-x-password-manager";
  onePasswordInstallUrl = "${amoLatestBaseUrl}${onePasswordSlug}/latest.xpi";

  # SVG Gobbler is not packaged in the rycee NUR firefox-addons set, so it is
  # delivered via AMO force-install instead. The GUID below comes from the
  # AMO API (services.addons.mozilla.org/api/v5/addons/addon/svg-gobbler/).
  svgGobblerId = "{7962ff4a-5985-4cf2-9777-4bb642ad05b8}";
  svgGobblerSlug = "svg-gobbler";
  svgGobblerInstallUrl = "${amoLatestBaseUrl}${svgGobblerSlug}/latest.xpi";

  librewolfUblockOriginListData = builtins.fromJSON (
    builtins.readFile ./_librewolf-ubo-default-lists.json
  );
  # Filtered from LibreWolf upstream defaults:
  # - adguard-spyware-url
  # - ublock-badware
  # - easylist
  # - urlhaus-1
  # - curben-phishing
  disabledLibrewolfLists = [
    "adguard-spyware-url"
    "ublock-badware"
    "easylist"
    "urlhaus-1"
    "curben-phishing"
  ];
  librewolfUblockOriginLists = builtins.filter (
    list: !(builtins.elem list disabledLibrewolfLists)
  ) librewolfUblockOriginListData.lists;

  # uBO "medium mode": block third-party scripts and frames by default.
  # Commonly-used sites are pre-whitelisted; other sites need interactive
  # whitelisting via the uBO popup (per-site 3p-script/3p-frame => noop).
  # See https://github.com/gorhill/uBlock/wiki/Blocking-mode:-medium-mode.
  ublockOriginMediumModeRules = [
    "behind-the-scene * * noop"
    "* * 3p-script block"
    "* * 3p-frame block"

    # Trusted sites: allow 3p scripts and frames.
    # Source-host match covers all subdomains.

    # Dev hosting & code collaboration
    "github.com * 3p-script noop"
    "github.com * 3p-frame noop"
    "github.dev * 3p-script noop"
    "github.dev * 3p-frame noop"
    "gitlab.com * 3p-script noop"
    "gitlab.com * 3p-frame noop"
    "bitbucket.org * 3p-script noop"
    "bitbucket.org * 3p-frame noop"
    "codeberg.org * 3p-script noop"
    "codeberg.org * 3p-frame noop"

    # Package registries & developer docs
    "hub.docker.com * 3p-script noop"
    "hub.docker.com * 3p-frame noop"
    "developer.mozilla.org * 3p-script noop"
    "developer.mozilla.org * 3p-frame noop"
    "developers.google.com * 3p-script noop"
    "developers.google.com * 3p-frame noop"
    "nixos.org * 3p-script noop"
    "nixos.org * 3p-frame noop"
    "formulae.brew.sh * 3p-script noop"
    "formulae.brew.sh * 3p-frame noop"

    # Q&A and knowledge
    "stackoverflow.com * 3p-script noop"
    "stackoverflow.com * 3p-frame noop"
    "stackexchange.com * 3p-script noop"
    "stackexchange.com * 3p-frame noop"
    "superuser.com * 3p-script noop"
    "superuser.com * 3p-frame noop"
    "askubuntu.com * 3p-script noop"
    "askubuntu.com * 3p-frame noop"
    "serverfault.com * 3p-script noop"
    "serverfault.com * 3p-frame noop"

    # Google productivity
    "docs.google.com * 3p-script noop"
    "docs.google.com * 3p-frame noop"
    "drive.google.com * 3p-script noop"
    "drive.google.com * 3p-frame noop"
    "mail.google.com * 3p-script noop"
    "mail.google.com * 3p-frame noop"
    "accounts.google.com * 3p-script noop"
    "accounts.google.com * 3p-frame noop"

    # Microsoft 365
    "teams.cloud.microsoft * 3p-script noop"
    "teams.cloud.microsoft * 3p-frame noop"
    "login.microsoftonline.com * 3p-script noop"
    "login.microsoftonline.com * 3p-frame noop"
    "login.live.com * 3p-script noop"
    "login.live.com * 3p-frame noop"
    "login.microsoft.com * 3p-script noop"
    "login.microsoft.com * 3p-frame noop"

    # Cloud consoles
    "cloud.google.com * 3p-script noop"
    "cloud.google.com * 3p-frame noop"

    # AI tools
    "chatgpt.com * 3p-script noop"
    "chatgpt.com * 3p-frame noop"
    "auth.openai.com * 3p-script noop"
    "auth.openai.com * 3p-frame noop"
    "claude.ai * 3p-script noop"
    "claude.ai * 3p-frame noop"
    "gemini.google.com * 3p-script noop"
    "gemini.google.com * 3p-frame noop"
    "notebooklm.google.com * 3p-script noop"
    "notebooklm.google.com * 3p-frame noop"
    "codeassist.google * 3p-script noop"
    "codeassist.google * 3p-frame noop"
    "codeassist.google.com * 3p-script noop"
    "codeassist.google.com * 3p-frame noop"
    "aistudio.google.com * 3p-script noop"
    "aistudio.google.com * 3p-frame noop"

    # Proton web properties
    "proton.me * 3p-script noop"
    "proton.me * 3p-frame noop"

    # Mozilla / extensions
    "addons.mozilla.org * 3p-script noop"
    "addons.mozilla.org * 3p-frame noop"
  ];

  extensionSettings = {
    "${ublockOriginId}" = {
      installation_mode = "force_installed";
      install_url = ublockOriginInstallUrl;
      private_browsing = true;
    };
    "${onePasswordId}" = {
      installation_mode = "force_installed";
      install_url = onePasswordInstallUrl;
    };
    "${svgGobblerId}" = {
      installation_mode = "force_installed";
      install_url = svgGobblerInstallUrl;
    };
  };

  # Per-profile package lists. Consumers wire these into
  # programs.<browser>.profiles.<name>.extensions.packages.
  primaryPackages = with firefox-addons; [
    ublock-origin
    raindropio
    cookie-autodelete
    simplelogin
    tab-stash
    languagetool
    web-archives
    tridactyl
    darkreader
    onepassword-password-manager
  ];

  workPackages =
    primaryPackages
    ++ (with firefox-addons; [
      foxyproxy-standard
      violentmonkey
      wappalyzer
    ]);

  ephemeralPackages =
    primaryPackages
    ++ (with firefox-addons; [
      print-edit-we
      save-page-we
    ]);
in
{
  extensionPolicies = {
    ExtensionSettings = extensionSettings;

    "3rdparty".Extensions."${ublockOriginId}" = {
      adminSettings = builtins.toJSON {
        assetsBootstrapLocation = librewolfUblockOriginListData.source;
      };
    };
  };

  inherit primaryPackages workPackages ephemeralPackages;

  extensionStorage."${ublockOriginId}".settings = {
    advancedUserEnabled = true;
    cloudStorageEnabled = true;
    showIconBadge = false;
    hostnameSwitchesString = builtins.concatStringsSep "\n" [
      "no-csp-reports: * true"
      "no-large-media: behind-the-scene false"
    ];
    dynamicFilteringString = builtins.concatStringsSep "\n" ublockOriginMediumModeRules;
    selectedFilterLists = librewolfUblockOriginLists ++ [
      # Additional regional lists
      "ara-0"

      # Additional generic ad blocking
      "adguard-generic"

      # Network / LAN protection
      "block-lan"

      # Additional lists to suppress cookie banners/annoyances
      "ublock-annoyances"
      "adguard-cookies"
      "ublock-cookies-adguard"
      # "fanboy-cookiemonster"
      # "ublock-cookies-easylist"
      "fanboy-thirdparty_social"
      "adguard-other-annoyances"
      "adguard-popup-overlays"
      "adguard-widgets"
    ];
  };
}
