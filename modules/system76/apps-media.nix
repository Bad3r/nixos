{ config, ... }:
let
  helpers =
    config._module.args.nixosAppHelpers
      or (throw "nixosAppHelpers not available - ensure meta/nixos-app-helpers.nix is imported");
  inherit (helpers) getApps;

  mediaAppNames = [
    "mpv"
    "nsxiv"
    "media-toolchain"
  ];
in
{
  configurations.nixos.system76.module.imports = getApps mediaAppNames;
}
