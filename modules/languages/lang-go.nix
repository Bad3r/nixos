{ config, ... }:
{
  flake.nixosModules.lang.go.imports =
    let
      inherit (config.flake.nixosModules) apps;
    in
    [
      apps.go
    ];
}
