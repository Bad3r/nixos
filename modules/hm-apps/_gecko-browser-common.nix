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
  bitwardenId = "{446900e4-71c2-419f-a6a7-df9c091e268b}";
  bitwardenSlug = "bitwarden-password-manager";
  ublockOriginInstallUrl = "${amoLatestBaseUrl}${ublockOriginSlug}/latest.xpi";
  bitwardenInstallUrl = "${amoLatestBaseUrl}${bitwardenSlug}/latest.xpi";
  librewolfUblockOriginListData = builtins.fromJSON (
    builtins.readFile ./_librewolf-ubo-default-lists.json
  );
  librewolfUblockOriginLists = librewolfUblockOriginListData.lists;
  # uBO "medium mode": block third-party scripts and frames by default.
  # Users whitelist trusted sites interactively via the uBO popup
  # (per-site 3p-script/3p-frame => noop), so expect site breakage until
  # a site is explicitly allowed. See
  # https://github.com/gorhill/uBlock/wiki/Blocking-mode:-medium-mode.
  ublockOriginMediumModeRules = [
    "behind-the-scene * * noop"
    "behind-the-scene * image noop"
    "behind-the-scene * 3p noop"
    "behind-the-scene * inline-script noop"
    "behind-the-scene * 1p-script noop"
    "behind-the-scene * 3p-script noop"
    "behind-the-scene * 3p-frame noop"
    "* * 3p-script block"
    "* * 3p-frame block"
  ];
  extensionSettings = {
    "${ublockOriginId}" = {
      installation_mode = "force_installed";
      install_url = ublockOriginInstallUrl;
      private_browsing = true;
    };
    "${bitwardenId}" = {
      installation_mode = "force_installed";
      install_url = bitwardenInstallUrl;
    };
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
    bitwarden
  ];

  extensionStorage."${ublockOriginId}".settings = {
    advancedUserEnabled = true;
    dynamicFilteringString = builtins.concatStringsSep "\n" ublockOriginMediumModeRules;
    selectedFilterLists = librewolfUblockOriginLists ++ [
      # Additional regional lists
      "ara-0"

      # Additional lists to suppress cookie banners/annoyances
      "ublock-annoyances"
      "adguard-cookies"
      "ublock-cookies-adguard"
      "fanboy-cookiemonster"
      "ublock-cookies-easylist"
    ];
  };
}
