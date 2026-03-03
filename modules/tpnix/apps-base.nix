{ config, ... }:
let
  helpers =
    config._module.args.nixosAppHelpers
      or (throw "nixosAppHelpers not available - ensure meta/nixos-app-helpers.nix is imported");
  inherit (helpers) getAllApps;
in
{
  configurations.nixos.tpnix.module.imports = getAllApps;
}
