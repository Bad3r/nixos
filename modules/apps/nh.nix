/*
  Package: nh
  Description: Nice helper CLI that streamlines common NixOS and Home Manager workflows.
  Homepage: https://github.com/viperML/nh
  Documentation: https://github.com/viperML/nh#readme
  Repository: https://github.com/viperML/nh

  Summary:
    * Provides short commands for switching configurations, cleaning generations, and running `nix flake` operations.
    * Offers profile management for system and user configurations with sensible defaults.

  Options:
    nh os switch: Rebuild and switch the current NixOS configuration.
    nh os boot: Build but do not activate the next boot generation.
    nh clean all: Garbage-collect dormant generations and store paths.

  Example Usage:
    * `nh os switch` — Equivalent to `sudo nixos-rebuild switch --flake .`, but shorter.
    * `nh hm switch` — Apply Home Manager changes from the flake.
    * `nh clean all` — Remove stale system and user generations safely.
*/

{
  flake.nixosModules.apps.nh =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.nh ];
    };
}
