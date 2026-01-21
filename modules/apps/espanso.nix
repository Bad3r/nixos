/*
  Package: espanso
  Description: Cross-platform text expander written in Rust.
  Homepage: https://espanso.org
  Documentation: https://espanso.org/docs/
  Repository: https://github.com/espanso/espanso

  Summary:
    * Detects when you type a keyword (trigger) and replaces it with predefined text (expansion).
    * Supports variables (date, shell, clipboard), forms, regex triggers, and app-specific configurations.

  Notes:
    * This module provides the enable flag for the Home Manager espanso service.
    * Package installation is handled by the Home Manager module, not this NixOS module.
    * Uses services namespace since espanso runs as a background service.
*/
_:
let
  EspansoModule =
    { lib, pkgs, ... }:
    {
      options.services.espanso.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable espanso.";
        };

        package = lib.mkPackageOption pkgs "espanso" { };
      };
    };
in
{
  flake.nixosModules.apps.espanso = EspansoModule;
}
