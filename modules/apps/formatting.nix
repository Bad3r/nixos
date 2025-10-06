/*
  Package: formatting
  Description: Collection bundle of common code formatters used across the repository.
  Homepage: https://github.com/vx/nixos
  Documentation: https://github.com/vx/nixos
  Repository: https://github.com/vx/nixos

  Summary:
    * Installs the project-standard formatter toolchain (e.g. `nixfmt`, `shfmt`, `prettier`) to ensure consistent styling across languages.
    * Intended for developers entering the repo's `nix develop` environment or running `nix fmt` locally.

  Options:
    formatting bundle: Provides formatter binaries; individual tools expose their own flags (see respective man pages).

  Example Usage:
    * `nix fmt` — Run the configured formatter suite on the working tree.
    * `nix develop` — Enter the development shell with all formatters available on `$PATH`.
*/

{
  flake.nixosModules.apps.formatting =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        biome
        nixfmt-rfc-style
        shellcheck
        shfmt
        treefmt
      ];
    };

}
