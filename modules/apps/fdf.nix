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

  flake.homeManagerModules.apps.fdf =
    { lib, osConfig, ... }:
    let
      cfg = lib.attrByPath [ "programs" "fdf" "extended" ] { enable = false; } osConfig;
    in
    {
      # Alongside the zsh keybindings (1050), after the fzf and atuin integrations.
      config = lib.mkIf cfg.enable {
        programs.zsh.initContent = lib.mkOrder 1050 ''
          # ^E runs fdf.
          fdf-widget() {
            zle -I
            ${lib.getExe cfg.package} <"$TTY"
            zle reset-prompt
          }
          zle -N fdf-widget
          bindkey -M viins '^E' fdf-widget
          bindkey -M vicmd '^E' fdf-widget
        '';
      };
    };
}
