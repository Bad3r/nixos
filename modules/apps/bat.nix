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
    { lib, ... }:
    {
      options.programs.bat.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable bat.";
        };
      };
    };
in
{
  flake.nixosModules.apps.bat = BatModule;
}
