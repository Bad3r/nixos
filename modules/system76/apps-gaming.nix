{ config, lib, ... }:
let
  helpers =
    config._module.args.nixosAppHelpers
      or (throw "nixosAppHelpers not available - ensure meta/nixos-app-helpers.nix is imported");
  inherit (helpers) getApps hasApp;

  desiredAppNames = [
    "steam"
    "wine-tools"
    "mangohud"
  ];

  availableAppNames = lib.filter hasApp desiredAppNames;
in
{
  configurations.nixos.system76.module.imports = getApps availableAppNames;
}
