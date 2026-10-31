/*
  Package: monitor-query
  Description: Shell helper library that reports active i3 monitor geometry.
  Repository: https://github.com/Bad3r/nixos
*/
_:
let
  MonitorQueryModule =
    { lib, ... }:
    {
      options.programs."monitor-query".extended.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to enable the monitor-query shell library overlay.";
      };
    };
in
{
  flake.nixosModules.apps."monitor-query" = MonitorQueryModule;
}
