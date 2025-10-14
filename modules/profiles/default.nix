{ lib, ... }:
{
  # Ensure the profiles namespace exists so downstream modules (for example
  # modules/profiles/workstation.nix) can merge into it without relying on
  # import-tree ordering.
  flake.nixosModules.profiles = lib.mkDefault { };
}
