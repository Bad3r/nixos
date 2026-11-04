/*
  Package: fdf
  Description: Interactive ripgrep with fzf live search and preview.
  Repository: https://github.com/Bad3r/nixos

  Summary:
    * Combines ripgrep and fzf for interactive fuzzy searching across files.
    * Re-runs ripgrep as you type for live search results.
    * Syntax-highlighted preview with bat showing context around matches.
    * Opens selected result in $EDITOR at the matching line number.
*/
_:
let
  FdfModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.fdf.extended;
    in
    {
      options.programs.fdf.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable fdf.";
        };

        package = lib.mkPackageOption pkgs "fdf" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.fdf = FdfModule;
}
