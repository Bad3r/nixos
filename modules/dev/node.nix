{ config, ... }:
{
  # Node toolchain (JS runtime + package managers) as a dev namespace
  flake.nixosModules.dev.node.imports = with config.flake.nixosModules.apps; [
    nodejs_22
    nodejs_24
    yarn
    nrm
  ];
}
