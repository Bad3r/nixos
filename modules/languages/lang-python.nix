{ config, ... }:
{
  flake.nixosModules.lang.python.imports =
    let
      inherit (config.flake.nixosModules) apps;
    in
    [
      apps.python
      apps.uv
    ];
}
