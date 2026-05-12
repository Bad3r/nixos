/*
  Internal: shared per-profile builder for Gecko browsers
  Description: Composes commonSettings/search/containers/extensions into a
  Home Manager `programs.<browser>.profiles.<name>` value so firefox.nix,
  floorp.nix, and librewolf.nix can stay symmetric. The NUR overlay is
  extended here once per browser module so the unfree firefox-addons
  (languagetool, wappalyzer, etc.) inherit the project-wide
  `allowUnfreePredicate`.

  Arguments:
    pkgs, inputs, lib, config: standard module args from the caller.
    cfg: the caller's privacy config (must define `enableWebRTC` and
         `enableDRM`, both booleans).

  Returns:
    mkProfile, extensionPolicies, primaryPackages, workPackages,
    ephemeralPackages.
*/

{
  pkgs,
  inputs,
  lib,
  config,
  cfg,
}:
let
  firefox-addons = (pkgs.extend inputs.dedupe_nur.overlays.default).nur.repos.rycee.firefox-addons;

  geckoPrefs = import ./_gecko-prefs.nix {
    inherit lib;
    fonts = if (config.stylix.enable or false) then config.stylix.fonts else null;
  };
  geckoSearch = import ./_gecko-search.nix { };
  geckoContainers = import ./_gecko-containers.nix { };
  geckoExtensions = import ./_gecko-extensions.nix { inherit firefox-addons; };

  mediaSettings = {
    "media.peerconnection.enabled" = cfg.enableWebRTC;
    "media.eme.enabled" = cfg.enableDRM;
    "media.gmp-widevinecdm.enabled" = cfg.enableDRM;
  };

  mkProfile =
    {
      id,
      packages,
      extraSettings ? { },
      containersForce ? false,
    }:
    {
      inherit id containersForce;
      settings = geckoPrefs.commonSettings // mediaSettings // extraSettings;
      inherit (geckoSearch) search;
      inherit (geckoContainers) containers;
      extensions = {
        force = true;
        inherit packages;
        settings = geckoExtensions.extensionStorage;
      };
    };
in
{
  inherit mkProfile;
  inherit (geckoExtensions)
    primaryPackages
    workPackages
    ephemeralPackages
    extensionPolicies
    ;
}
