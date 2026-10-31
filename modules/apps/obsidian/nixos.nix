/*
  Package: obsidian
  Description: Local-first Markdown knowledge base and note-taking app with graph-based linking.
  Homepage: https://obsidian.md/
  Documentation: https://help.obsidian.md/
  Repository: nil

  Summary:
    * Organizes notes as Markdown files with bidirectional links, graph view, daily notes, templates, and extensible plugin marketplace.
    * Supports end-to-end encrypted sync (paid), community themes, and plugins for task management, spaced repetition, and more.
*/
_:
let
  ObsidianModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.obsidian.extended;
    in
    {
      options.programs.obsidian.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable obsidian.";
        };

        package = lib.mkPackageOption pkgs "obsidian" { };
      };

      config = lib.mkIf cfg.enable {

        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  nixpkgs.allowedUnfreePackages = [ "obsidian" ];
  flake.nixosModules.apps.obsidian = ObsidianModule;
}
