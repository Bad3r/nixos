{ ... }:
{
  flake.nixosModules.base.imports = [
    ./flake-output.nix
    ./nixos-home-manager-collect.nix
    ./nixos-role-helpers.nix
    ./nixos-app-helpers.nix
  ];
}
