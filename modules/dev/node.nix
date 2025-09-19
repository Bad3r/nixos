{ config, ... }:
{
  # Node toolchain (JS runtime + package managers) as a dev namespace
  flake.nixosModules.dev.node.imports =
    let
      inherit (config.flake.nixosModules) apps;
    in
    [
      apps.nodejs_22
      apps.nodejs_24
      apps.yarn
      apps.nrm
    ];
}
