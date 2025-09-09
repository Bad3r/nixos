{ config, ... }:
{
  flake.nixosModules.pc.imports = with config.flake.nixosModules; [ base ];
}
