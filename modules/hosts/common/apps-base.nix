/*
  Apps Auto-Import (common baseline)

  Imports every app module from flake.nixosModules.apps into the host module
  tree. All app modules default to disabled; only apps explicitly enabled in
  apps-enable.nix activate.

  This module intentionally does NOT gate on `shareCommon`: importing a module
  whose options default to disabled is a no-op for hosts that opt out of the
  common baseline. Reading `config.flake.lib.nixos.hosts.<host>.shareCommon`
  here forces a merge of `flake.lib.nixos` (which collects helpers from
  meta/nixos-app-helpers.nix and host flags from hosts/common/registry.nix)
  and creates an eval-order conflict with the wfuzz custom-overlay's lookup
  of `config.programs.wfuzz.extended`.

  Usage:
    1. Create module in modules/apps/
    2. Enable in apps-enable.nix
*/
{ config, ... }:
let
  helpers =
    config._module.args.nixosAppHelpers
      or (throw "nixosAppHelpers not available - ensure meta/nixos-app-helpers.nix is imported");
  inherit (helpers) getAllApps;
in
{
  configurations.nixos.system76.module.imports = getAllApps;
  configurations.nixos.tpnix.module.imports = getAllApps;
}
