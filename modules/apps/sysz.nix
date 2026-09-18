/*
  Package: sysz
  Description: fzf terminal UI for systemctl.
  Homepage: https://github.com/joehillen/sysz
  Documentation: https://github.com/joehillen/sysz#usage
  Repository: https://github.com/joehillen/sysz

  Summary:
    * Picks units and unit states through fzf, then runs the chosen systemctl action on them.
    * Covers system and user units, with a live `systemctl status` preview and journal following.

  Options:
    -u, --user: Only show user units.
    --sys, --system: Only show system units.
    -s, --state <state>: Only show units in the given state, for example `failed`.
    -V, --verbose: Print the systemctl commands that run.

  Example Usage:
    * `sysz` -- Pick units, then an action.
    * `sysz -u -s failed` -- Triage failed user units.
    * `sysz restart` -- Restart the picked units.
*/
_:
let
  SyszModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.sysz.extended;
    in
    {
      options.programs.sysz.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable sysz.";
        };

        package = lib.mkPackageOption pkgs "sysz" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.sysz = SyszModule;
}
