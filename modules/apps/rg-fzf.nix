/*
  Package: rg-fzf
  Description: Interactive ripgrep with fzf live search and preview.
  Homepage: N/A (custom package)
  Documentation: See package meta.longDescription

  Summary:
    * Combines ripgrep and fzf for interactive fuzzy searching across files.
    * Re-runs ripgrep as you type for live search results.
    * Syntax-highlighted preview with bat showing context around matches.
    * Opens selected result in $EDITOR at the matching line number.

  Usage:
    rg-fzf [INITIAL_QUERY] [DIRECTORY]

  Keybindings:
    Enter     - Open selected file in $EDITOR at line
    Ctrl-/    - Toggle preview window
    Ctrl-u/f  - Scroll preview up/down
*/
_:
let
  RgFzfModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.rg-fzf.extended;
    in
    {
      options.programs.rg-fzf.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable rg-fzf.";
        };

        package = lib.mkPackageOption pkgs "rg-fzf" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.rg-fzf = RgFzfModule;
}
