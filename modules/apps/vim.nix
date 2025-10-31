/*
  Package: vim
  Description: Classic Vim text editor with scripting, modal editing, and extensive plugin ecosystem.
  Homepage: https://www.vim.org/
  Documentation: https://vimhelp.org/
  Repository: https://github.com/vim/vim

  Summary:
    * Provides modal editing, macros, registers, and a rich scripting interface (Vimscript, Lua) for efficient text editing.
    * Supports syntax highlighting for hundreds of languages, digraphs, splits/tabs, and integration with external tools and plugins.

  Options:
    vim <files>: Edit files interactively.
    vim -u NONE: Launch without any configuration for troubleshooting.
    vim -O file1 file2: Open files in vertically split windows.
    vim +'command' <file>: Execute ex commands on startup (e.g., `+"set nu"`).

  Example Usage:
    * `vim ~/.config/nixos/configuration.nix` — Edit a configuration file with syntax highlighting.
    * `vim -u NONE -N` — Start with no configuration in nocompatible mode to debug issues.
    * `vim +'PlugUpdate' +qa` — Update plugins using vim-plug in automation scripts.
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.vim.extended;
  VimModule = {
    options.programs.vim.extended = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true; # Backward compatibility - TODO: flip to false in Phase 2
        description = lib.mdDoc "Whether to enable vim.";
      };

      package = lib.mkPackageOption pkgs "vim" { };
    };

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [ cfg.package ];
    };
  };
in
{
  flake.nixosModules.apps.vim = VimModule;
}
