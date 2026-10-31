/*
  Package: glow
  Description: Terminal markdown renderer with styled previews, pager mode, and theme selection.
  Homepage: https://github.com/charmbracelet/glow
  Documentation: https://github.com/charmbracelet/glow#readme
  Repository: https://github.com/charmbracelet/glow

  Summary:
    * Renders Markdown with selectable dark/light themes directly in the terminal or pager.
    * Supports local and remote sources, TUI navigation, and export to plaintext or JSON for further tooling.

  Options:
    glow --pager: Display the rendered output in a pager.
    glow --style <dark|light>: Override the automatic theme choice.
*/
_:
let
  GlowModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.glow.extended;
    in
    {
      options.programs.glow.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable glow.";
        };

        package = lib.mkPackageOption pkgs "glow" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.glow = GlowModule;
}
