/*
  Package: ungoogled-chromium
  Description: Chromium build with Google-integration stripped out, prioritizing privacy and manual control over updates.
  Homepage: https://ungoogled-software.github.io/ungoogled-chromium/
  Documentation: https://github.com/ungoogled-software/ungoogled-chromium
  Repository: https://github.com/ungoogled-software/ungoogled-chromium

  Summary:
    * Mirrors the NixOS ungoogled-chromium app module into Home Manager.
    * Reuses the wrapped package so the default Chromium Web Store extension is available in HM-managed profiles too.
*/

_: {
  flake.homeManagerModules.apps.ungoogled-chromium =
    {
      osConfig,
      lib,
      ...
    }:
    let
      nixosEnabled = lib.attrByPath [
        "programs"
        "ungoogled-chromium"
        "extended"
        "enable"
      ] false osConfig;
      finalPackage = lib.attrByPath [
        "programs"
        "ungoogled-chromium"
        "extended"
        "finalPackage"
      ] null osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.chromium = {
          enable = true;
          package = finalPackage;
        };
      };
    };
}
