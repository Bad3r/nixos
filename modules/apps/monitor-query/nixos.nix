/*
  Package: monitor-query
  Description: Shell helper library that reports active i3 monitor geometry,
    sourced by scratchpad scripts to compute placement/size.
  Repository: https://github.com/Bad3r/nixos

  Notes:
    * Generated via writeText from _script.nix and exposed by
      modules/apps/monitor-query/overlay.nix.
    * Sourced by modules/apps/i3wm/scratchpad.nix as a path
      (`. "${pkgs.monitor-query}"`); it is a single file, not a derivation
      with bin/share/ outputs.
    * The module declares only `extended.enable`. There is no `package`
      option because no consumer reads `cfg.package`; callers use
      `pkgs.monitor-query` directly. The module's sole job is to provide
      the toggle that `modules/apps/monitor-query/overlay.nix` gates on.
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
