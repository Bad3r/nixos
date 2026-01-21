/*
  Package: neovim
  Description: Modern Vim fork featuring Lua APIs, asynchronous plugins, and improved UI capabilities.
  Homepage: https://neovim.io/
  Documentation: https://neovim.io/doc/user/
  Repository: https://github.com/neovim/neovim

  Summary:
    * Enhances Vim with embedded Lua scripting, Tree-sitter integration, LSP client, terminal emulator, and RPC APIs for external UIs.
    * Maintains compatibility with Vimscript while enabling performant plugin ecosystems like Lazy.nvim, Telescope, and nvim-cmp.

  Notes:
    * This module provides the base neovim-unwrapped package for nixvim to wrap.
    * Package installation is handled by the nixvim home-manager module, not this NixOS module.
    * Enable this module to activate nixvim configuration in home-manager.
*/
_:
let
  NeovimModule =
    { lib, pkgs, ... }:
    {
      options.programs.neovim.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable neovim (via nixvim).";
        };

        package = lib.mkPackageOption pkgs "neovim-unwrapped" { };
      };

      # No config block - nixvim handles package installation via home-manager
    };
in
{
  flake.nixosModules.apps.neovim = NeovimModule;
}
