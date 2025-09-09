{ config, ... }:
{
  flake.modules.nixos.lang.node.imports = with config.flake.modules.nixos.apps; [
    nodejs_22
    nodejs_24
    yarn
    nrm
  ];
}
