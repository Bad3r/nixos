{ config, ... }:
{
  flake.nixosModules.lang.go.imports = with config.flake.nixosModules.apps; [
    go
  ];
}
