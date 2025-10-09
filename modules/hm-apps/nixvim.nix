/*
  Package: nixvim
  Description: Declarative Neovim configuration powered by the nix-community/nixvim module collection.
  Homepage: https://github.com/nix-community/nixvim
  Documentation: https://nix-community.github.io/nixvim
  Repository: https://github.com/nix-community/nixvim

  Summary:
    * Exposes Neovim configuration as Nix options so editor state, plugins, and key maps stay reproducible.
    * Provides first-class modules for plugin ecosystems (treesitter, LSP, UI helpers) and integrates with Stylix theming targets.

  Notes:
    * Imports the upstream Home Manager nixvim module from `inputs.nixvim` and layers Stylix’ nixvim target when enabled.
    * Ships the `glow.nvim` preview plugin with Markdown-only lazy loading and convenient preview keymaps.
*/

{
  flake.homeManagerModules.apps.nixvim =
    {
      config,
      inputs,
      lib,
      ...
    }:
    let
      inherit (lib) attrByPath mkDefault optional;
      stylixModule = attrByPath [ "stylix" "targets" "nixvim" "exportedModule" ] null config;
      glowKeymaps = [
        {
          mode = [
            "n"
            "v"
          ];
          key = "<M-V>"; # Alt+Shift+V
          action = "<cmd>Glow<CR>";
          options = {
            desc = "Open Glow markdown preview";
            silent = true;
          };
        }
        {
          mode = "n";
          key = "<leader>V"; # <Space> + Shift + V
          action = "<cmd>Glow!<CR>";
          options = {
            desc = "Close Glow markdown preview";
            silent = true;
          };
        }
      ];
    in
    {
      imports = [ inputs.nixvim.homeModules.nixvim ] ++ optional (stylixModule != null) stylixModule;

      stylix.targets.nixvim.enable = mkDefault true;

      programs.nixvim = {
        enable = true;
        globals.mapleader = mkDefault " ";
        dependencies.glow.enable = true;

        plugins = {
          glow = {
            enable = true;
            lazyLoad.enable = true;
            lazyLoad.settings.ft = "markdown";
            settings = {
              border = "rounded";
              width = 120;
              glow_path = null; # rely on PATH/populated dependency
            };
          };
          lz-n.enable = true;
        };

        keymaps = glowKeymaps;
      };
    };
}
