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
    * Uses services namespace since espanso runs as a background service.
    * HM services.espanso does not support nullable package - HM handles installation.
*/
_:
let
  EspansoModule =
    { lib, ... }:
    {
      options.services.espanso.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable espanso.";
        };
      };
    };
in
{
  flake.nixosModules.apps.espanso = EspansoModule;
}
