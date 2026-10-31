/*
  Package: nix-index
  Description: File database for nixpkgs that answers which package provides a file or command.
  Homepage: https://github.com/nix-community/nix-index
  Documentation: https://github.com/nix-community/nix-index#usage
  Repository: https://github.com/NixOS/nix-index

  Options:
    nix-locate --top-level <pattern>: Report only top-level package attributes.
    nix-locate --whole-name <pattern>: Match the whole file name rather than a substring.

  Notes:
    * Prebuilt database from nix-index-database.
    * Replaces command-not-found in bash and zsh.
*/
{ inputs, ... }:
let
  NixIndexModule =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.programs."nix-index".extended;
    in
    {
      imports = [ inputs.nix-index-database.nixosModules.nix-index ];

      options.programs.nix-index.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable nix-index.";
        };
      };

      config = {
        # The database module enables nix-index and its own package by default.
        programs.nix-index-database.enable = cfg.enable;

        programs.nix-index = lib.mkIf cfg.enable {
          enable = true;
          enableBashIntegration = true;
          enableZshIntegration = true;
        };
      };
    };
in
{
  flake.nixosModules.apps.nix-index = NixIndexModule;
}
