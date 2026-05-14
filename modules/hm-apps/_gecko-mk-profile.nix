/*
  Internal: shared per-profile builder for Gecko browsers
  Description: Composes commonSettings/containers/extensions/bookmarks into a
  Home Manager `programs.<browser>.profiles.<name>` value so firefox.nix,
  floorp.nix, and librewolf.nix can stay symmetric. The NUR overlay is
  extended here once per browser module so the unfree firefox-addons
  (languagetool, wappalyzer, etc.) inherit the project-wide
  `allowUnfreePredicate`.

  Arguments:
    pkgs, inputs, lib, config: standard module args from the caller.
  Returns:
    mkProfile, policies, primaryPackages, workPackages, ephemeralPackages.
*/

{
  pkgs,
  inputs,
  lib,
  config,
}:
let
  firefox-addons = (pkgs.extend inputs.dedupe_nur.overlays.default).nur.repos.rycee.firefox-addons;

  geckoPrefs = import ./_gecko-prefs.nix {
    inherit lib;
    fonts = if (config.stylix.enable or false) then config.stylix.fonts else null;
  };
  geckoContainers = import ./_gecko-containers.nix { };
  geckoBookmarks = import ./_gecko-bookmarks.nix { inherit lib; };
  geckoExtensions = import ./_gecko-extensions.nix {
    inherit
      config
      firefox-addons
      lib
      pkgs
      ;
  };
  geckoPolicies = import ./_gecko-policies.nix { };

  bookmarksFile = lib.attrByPath [
    "sops"
    "templates"
    "gecko/bookmarks"
    "path"
  ] null config;

  policies = lib.recursiveUpdate geckoPolicies.policies geckoExtensions.extensionPolicies;

  mkProfile =
    {
      id,
      packages,
      extraSettings ? { },
      containersForce ? true,
    }:
    {
      inherit id containersForce;
      settings =
        geckoPrefs.commonSettings
        // geckoExtensions.sidebarSettings
        // geckoExtensions.toolbarSettings
        // (geckoBookmarks.settings bookmarksFile)
        // extraSettings;
      inherit (geckoContainers) containers;
      extensions = {
        force = true;
        inherit packages;
        settings = geckoExtensions.extensionStorage;
      };
    };
in
{
  inherit mkProfile policies;
  inherit (geckoExtensions)
    nativeMessagingHosts
    primaryPackages
    workPackages
    ephemeralPackages
    ;
}
