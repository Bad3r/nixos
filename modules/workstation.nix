# workstation.nix - Development workstation configuration

{ config, ... }:
{
  flake.modules.nixos.workstation.imports = with config.flake.modules.nixos; [ pc ];
}
