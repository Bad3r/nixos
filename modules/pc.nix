# pc.nix - Personal computer configuration

{ config, ... }:
{
  flake.modules.nixos.pc.imports = with config.flake.modules.nixos; [ base ];
}
