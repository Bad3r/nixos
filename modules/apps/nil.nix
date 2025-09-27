/*
  Package: nil
  Description: Fast Nix language server offering diagnostics, completions, and formatting.
  Homepage: https://github.com/oxalica/nil
  Documentation: https://github.com/oxalica/nil#readme
  Repository: https://github.com/oxalica/nil

  Summary:
    * Provides Language Server Protocol (LSP) features like hover info, go-to-definition, and code actions for Nix.
    * Integrates with popular editors and includes experimental formatting and eval previews.

  Options:
    --version: Print the language server version shipped in the build.
    --help: Display all available server flags and usage information.
    --stdio: Run the language server over stdio for LSP integrations.
*/

{
  flake.nixosModules.apps.nil =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.nil ];
    };
}
