{ config, ... }:
let
  inherit (config.flake.lib.nixos) getApps;
in
{
  flake.nixosModules.lang.python.imports = getApps [
    "python"
    "uv"
  ];
}
