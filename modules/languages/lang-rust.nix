{ config, ... }:
{
  flake.nixosModules.lang.rust.imports =
    let
      inherit (config.flake.nixosModules) apps;
    in
    [
      apps.rustc
      apps.cargo
    ];
}
