{ config, ... }:
{
  flake.modules.nixos.lang.rust.imports = with config.flake.modules.nixos.apps; [
    rustc
    cargo
  ];
}
