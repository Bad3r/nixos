_: {
  flake.nixosModules.base.imports = [
    ./flake-output.nix
    ./nixos-roles-preload.nix
    ./nixos-role-helpers.nix
    ./nixos-app-helpers.nix
  ];
}
