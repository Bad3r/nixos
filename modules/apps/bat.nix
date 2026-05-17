/*
  Package: bat
  Description: Syntax-highlighted cat alternative with Git-aware paging and theming.
  Homepage: https://github.com/sharkdp/bat
  Documentation: https://github.com/sharkdp/bat#usage
  Repository: https://github.com/sharkdp/bat

  Summary:
    * Prints files with syntax highlighting, line numbers, Git integration, and automatic paging.
    * Supports multiple themes, custom highlighting assets, and convenient diff/line filtering switches.

  Notes:
    * HM programs.bat does not support nullable package - HM handles installation.
*/
_:
let
  BatModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.bat.extended;
      batman = pkgs.bat-extras.batman;
    in
    {
      options.programs.bat.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable bat.";
        };
      };

      config = lib.mkIf cfg.enable {
        host.defaults.pager = {
          command = lib.mkOverride 900 "${lib.getExe pkgs.bat} --plain --paging=always";
          man = {
            pager = lib.mkOverride 900 "env BATMAN_IS_BEING_MANPAGER=yes ${lib.getExe batman}";
            roffopt = lib.mkOverride 900 "-c";
            width = lib.mkOverride 900 "120";
          };
        };
      };
    };
in
{
  flake.nixosModules.apps.bat = BatModule;
}
