/*
  Internal: shared Gecko-browser enterprise policies
  Description: Non-default LibreWolf distribution policies applied to
    Firefox and LibreWolf.

  Source:
    https://codeberg.org/librewolf/settings/src/branch/master/distribution/policies.json

  Notes:
    * Includes only upstream policy entries that set a non-default value.
    * Omits LibreWolf's inert localhost WebsiteFilter sentinel.
    * Omits NoDefaultBookmarks because it disables the same defaultBookmarks
      feature used by browser.bookmarks.file imports.
*/

_:
let
  geckoSearch = import ./_gecko-search.nix { };
in
{
  policies = {
    AppUpdateURL = "https://localhost";
    DisableAppUpdate = true;
    OverrideFirstRunPage = "";
    OverridePostUpdatePage = "";
    DisableSystemAddonUpdate = true;
    DisableFirefoxStudies = true;
    DisableTelemetry = true;
    DisableFeedbackCommands = true;
    DisablePocket = true;
    ExtensionSettings = {
      "*" = {
        blocked_install_message = "Extensions are managed through Nix and cannot be installed from the browser.";
        installation_mode = "allowed";
        allowed_types = [
          "dictionary"
          "extension"
          "sitepermission"
          "theme"
        ];
      };
    };

    EnableTrackingProtection = {
      Value = true;
      Category = "strict";
      BaselineExceptions = true;
      ConvenienceExceptions = false;
    };
    Cookies.Allow = [ "https://github.com" ];

    DNSOverHTTPS = {
      Enabled = true;
      ProviderURL = "https://adblock.dns.mullvad.net/dns-query";
      Fallback = false;
    };
    SkipTermsOfUse = true;
  }
  // geckoSearch.policies;
}
