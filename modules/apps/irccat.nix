/*
  Package: irccat
  Description: Relay that posts messages from scripts, webhooks, and other applications into IRC channels.
  Homepage: https://github.com/irccloud/irccat
  Documentation: https://github.com/irccloud/irccat#readme
  Repository: https://github.com/irccloud/irccat

  Summary:
    * Joins an IRC server as a bot and forwards text received on a TCP listener, an HTTP endpoint, or a webhook to channels or users.
    * Runs commands from IRC through configured handler scripts, restricted by an auth-by-hostmask or auth-by-address allowlist.

  Options:
    -config <path>: Read the YAML configuration from a specific file.
    -debug: Print raw IRC lines.

  Notes:
    * The package is installed; no service unit is defined, so the bot runs only when started with a config file.
*/
_:
let
  IrccatModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.irccat.extended;
    in
    {
      options.programs.irccat.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable irccat.";
        };

        package = lib.mkPackageOption pkgs "irccat" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.irccat = IrccatModule;
}
