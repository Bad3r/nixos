{ config, ... }:
{
  # Node toolchain (JS runtime + package managers) as a dev namespace
  flake.modules.nixos.dev.node.imports = with config.flake.modules.nixos.apps; [
    nodejs_22
    nodejs_24
    yarn
    nrm
  ];
}
