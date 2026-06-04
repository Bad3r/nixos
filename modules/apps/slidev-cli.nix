/*
  Package: slidev-cli
  Description: Presentation slides for developers.
  Homepage: https://sli.dev
  Documentation: https://sli.dev/guide/
  Repository: https://github.com/slidevjs/slidev

  Summary:
    * Builds and serves Markdown-based presentation decks with Vue-powered interactive components.
    * Exports slides to PDF, PNG, SPA, or hosted applications for sharing and publishing.

  Options:
    init: Create a new Slidev project from an optional template.
    export: Export the slide deck to PDF, PNG, or other supported targets.
    build: Build the deck as a static single-page application.
    --remote: Listen on all network interfaces when serving a deck.
*/
_:
let
  SlidevCliModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.slidev-cli.extended;
    in
    {
      options.programs.slidev-cli.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable slidev-cli.";
        };

        package = lib.mkPackageOption pkgs "slidev-cli" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.slidev-cli = SlidevCliModule;
}
