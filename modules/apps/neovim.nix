/*
  Package: neovim
  Description: Modern Vim fork featuring Lua APIs, asynchronous plugins, and improved UI capabilities.
  Homepage: https://neovim.io/
  Documentation: https://neovim.io/doc/user/
  Repository: https://github.com/neovim/neovim

  Summary:
    * Enhances Vim with embedded Lua scripting, Tree-sitter integration, LSP client, terminal emulator, and RPC APIs for external UIs.
    * Maintains compatibility with Vimscript while enabling performant plugin ecosystems like Lazy.nvim, Telescope, and nvim-cmp.

  Options:
    nvim <files>: Edit files and directories interactively.
    nvim --headless -c <cmd>: Run commands or scripts without a UI (use for automation).
    nvim --clean: Start without user configuration for troubleshooting.
    nvim +'PlugUpdate' +qa: Example of running plugin updates in batch.

  Example Usage:
    * `nvim main.rs` — Edit a Rust source file with LSP/autocomplete support when configured.
    * `nvim --headless +'lua print(vim.version())' +qa` — Query Neovim version in CI pipelines.
    * `nvim --clean init.vim` — Inspect configuration issues by launching with defaults.
*/

{
  flake.nixosModules.apps.neovim =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.neovim ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.neovim ];
    };
}
