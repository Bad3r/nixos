{ config, ... }:
let
  inherit (config.flake.lib.nixos) getApps;
in
{
  # Node toolchain (JS runtime + package managers) as a dev namespace
  flake.nixosModules.dev.node.imports = getApps [
    "nodejs_22"
    "nodejs_24"
    "yarn"
    "nrm"
  ];
}
