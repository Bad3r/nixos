/*
  Package: discordo
  Description: Discord terminal client with keyboard-driven navigation.
  Homepage: https://github.com/ayn2op/discordo
  Documentation: https://github.com/ayn2op/discordo#readme
  Repository: https://github.com/ayn2op/discordo

  Summary:
    * Provides a terminal interface for Discord servers, channels, and messages.
    * Reads configuration from $XDG_CONFIG_HOME/discordo/config.toml.

  Example Usage:
    * `discordo` -- Launch the client and sign in interactively.
*/
_:
let
  DiscordoModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.discordo.extended;
    in
    {
      options.programs.discordo.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable discordo.";
        };

        package = lib.mkPackageOption pkgs "discordo" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.discordo = DiscordoModule;
}
