/*
  Package: logseq
  Description: Knowledge management and collaboration tool
  Homepage: https://logseq.com/
  Documentation: https://docs.logseq.com/
  Repository: https://github.com/logseq/logseq

  Summary:
    * Supports outlining, note-taking, and graph visualization.
*/
{ inputs, ... }:
let
  LogseqModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.logseq.extended;
      basePackage = inputs.nix-logseq-git-flake.packages.${pkgs.stdenv.hostPlatform.system}.logseq;
    in
    {
      options.programs.logseq.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable Logseq.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = basePackage;
          description = "The Logseq package to use.";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.logseq = LogseqModule;
}
