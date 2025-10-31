/*
  Package: starship
  Description: Cross-shell prompt written in Rust with configurable modules.
  Homepage: https://starship.rs/
  Documentation: https://starship.rs/config/
  Repository: https://github.com/starship/starship

  Summary:
    * Provides a fast, informative prompt that works with Bash, Zsh, Fish, and other shells.
    * Offers modular configuration for Git status, language runtimes, kubectl context, and system metrics.

  Options:
    --print-config: Output the merged configuration for debugging and sharing.
    --help: Display usage details for all starship subcommands and flags.
    --version: Show the currently installed starship release.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  StarshipModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.starship.extended;
    in
    {
      options.programs.starship.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = lib.mdDoc "Whether to enable starship.";
        };

        package = lib.mkPackageOption pkgs "starship" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.starship = StarshipModule;
}
