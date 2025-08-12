# flake-parts-modules.nix - Flake Parts Modules

{ inputs, ... }:
{
  imports = [ inputs.flake-parts.flakeModules.modules ];
}