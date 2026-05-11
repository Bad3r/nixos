/*
  Internal: shared Gecko-browser configuration
  Description: Common Firefox, Floorp, and LibreWolf extension policy and uBlock Origin settings.

  Summary:
    * Keeps shared extension IDs, AMO install URLs, and NUR extension packages in one place.
    * Mirrors LibreWolf's uBlock Origin default filter-list selection for Home Manager profiles.
    * Stays underscore-prefixed so automatic module discovery does not import it directly.
*/

{ firefox-addons }:
let
  # AMO's `/latest/<slug>/latest.xpi` endpoint accepts a URL-safe slug and
  # redirects to the current signed XPI. The extension ID (`uBlock0@...`,
  # `{GUID}`) must be used as the ExtensionSettings policy key, but the ID
  # contains characters that require percent-encoding in URLs, so slugs are
  # used for the install URL to keep the path URL-safe.
  amoLatestBaseUrl = "https://addons.mozilla.org/firefox/downloads/latest/";
  ublockOriginId = "uBlock0@raymondhill.net";
  ublockOriginSlug = "ublock-origin";
  onePasswordId = "{d634138d-c276-4fc8-924b-40a0ea21d284}";
  onePasswordSlug = "1password-x-password-manager";
  # bitwardenId = "{446900e4-71c2-419f-a6a7-df9c091e268b}";
  # bitwardenSlug = "bitwarden-password-manager";
  ublockOriginInstallUrl = "${amoLatestBaseUrl}${ublockOriginSlug}/latest.xpi";
  onePasswordInstallUrl = "${amoLatestBaseUrl}${onePasswordSlug}/latest.xpi";
  # bitwardenInstallUrl = "${amoLatestBaseUrl}${bitwardenSlug}/latest.xpi";
  librewolfUblockOriginListData = builtins.fromJSON (
    builtins.readFile ./_librewolf-ubo-default-lists.json
  );
  # Commented out from LibreWolf upstream defaults (filtered below):
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
  # Commonly-used sites are pre-whitelisted below; other sites need
  # interactive whitelisting via the uBO popup (per-site
  # 3p-script/3p-frame => noop). See
  # https://github.com/gorhill/uBlock/wiki/Blocking-mode:-medium-mode.
  ublockOriginMediumModeRules = [
    "behind-the-scene * * noop"
    "* * 3p-script block"
    "* * 3p-frame block"

    # Trusted sites: allow 3p scripts and frames
    # Source-host match covers all subdomains

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
    # "${bitwardenId}" = {
    #   installation_mode = "force_installed";
    #   install_url = bitwardenInstallUrl;
    # };
  };
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

  extensionPackages = with firefox-addons; [
    ublock-origin
    onepassword-password-manager
    # bitwarden
  ];

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
