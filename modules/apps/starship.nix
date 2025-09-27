/*
  Package: starship
  Description: Cross-shell prompt written in Rust with configurable modules.
  Homepage: https://starship.rs/
  Documentation: https://starship.rs/config/
  Repository: https://github.com/starship/starship

  Summary:
    * Provides a fast, informative prompt that works with Bash, Zsh, Fish, and other shells.
    * Offers modular configuration for Git status, language runtimes, kubectl context, and system metrics.

  Options:
    --print-config: Output the merged configuration for debugging and sharing.
    --help: Display usage details for all starship subcommands and flags.
    --version: Show the currently installed starship release.
*/

{
  flake.nixosModules.apps.starship =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.starship ];
    };
}
