/*
  Package: vim
  Description: Classic Vim text editor with scripting, modal editing, and extensive plugin ecosystem.
  Homepage: https://www.vim.org/
  Documentation: https://vimhelp.org/
  Repository: https://github.com/vim/vim

  Summary:
    * Modal editing with macros, registers, and Vimscript scripting.
    * Syntax highlighting for hundreds of languages, splits, tabs, and plugins.

  Options:
    vim -u NONE: Launch without any configuration for troubleshooting.
    vim -O file1 file2: Open files in vertically split windows.
    vim +'command' <file>: Execute ex commands on startup (e.g., `+"set nu"`).
*/
_:
let
  VimModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.vim.extended;
    in
    {
      options.programs.vim.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable vim.";
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
