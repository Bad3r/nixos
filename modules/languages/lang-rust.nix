{ config, ... }:
let
  inherit (config.flake.lib.nixos) getApps;
in
{
  flake.nixosModules.lang.rust.imports = getApps [
    "rustc"
    "cargo"
  ];
}
