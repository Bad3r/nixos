{ config, ... }:
{
  flake.nixosModules.lang.rust.imports = with config.flake.nixosModules.apps; [
    rustc
    cargo
  ];
}
