/*
  Package: espanso
  Description: Cross-platform text expander written in Rust.
  Homepage: https://espanso.org
  Documentation: https://espanso.org/docs/
  Repository: https://github.com/espanso/espanso

  Summary:
    * Replaces typed keywords (triggers) with predefined text (expansions).
    * Supports variables (date, shell, clipboard), forms, regex triggers, and app-specific configurations.
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
