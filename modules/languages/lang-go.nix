{ config, ... }:
{
  flake.modules.nixos.lang.go.imports = with config.flake.modules.nixos.apps; [
    go
  ];
}
