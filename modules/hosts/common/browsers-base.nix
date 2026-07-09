/*
  Browsers Auto-Import (common baseline)

  Imports every browser module from flake.nixosModules.browsers into the host
  module tree, mirroring apps-base.nix. All browser modules default to
  disabled; only browsers explicitly enabled in apps-enable.nix activate
  (their `programs.<name>.extended.enable` option paths are unchanged by the
  modules/browsers/ layout).

  This module does not read `shareCommon` itself. The host constructor imports
  the aggregate common module only for hosts opted in through the registry;
  reading the registry from this browser-import layer would force
  `flake.lib.nixos` while custom overlays are still resolving app options.

  Usage:
    1. Create module in modules/browsers/<name>/apps.nix
    2. Enable in apps-enable.nix
*/
{ config, ... }:
let
  helpers =
    config._module.args.nixosBrowserHelpers
      or (throw "nixosBrowserHelpers not available - ensure meta/nixos-browser-helpers.nix is imported");
  inherit (helpers) getAllBrowsers;
in
{
  flake.nixosModules.hosts-common.imports = getAllBrowsers;
}
