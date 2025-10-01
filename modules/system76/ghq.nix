{
  config,
  lib,
  ...
}:
let
  mirrorRepos = [
    "NixOS/nixpkgs"
    "NixOS/nixos-hardware"
    "nix-community/home-manager"
    "nix-community/stylix"
    "nix-community/nixvim"
    "cachix/git-hooks.nix"
    "mightyiam/files"
    "Mic92/sops-nix"
    "numtide/treefmt-nix"
    "vic/import-tree"
  ];
  mirrorModule = {
    programs.ghqMirror = {
      enable = true;
      root = "/git";
      repos = mirrorRepos;
    };
  };
  ghqRootModule =
    let
      nixosModules = (config.flake or { }).nixosModules or { };
    in
    lib.attrByPath [ "git" "ghq-root" ] null nixosModules;
in
{
  configurations.nixos.system76.module = _: {
    imports = lib.optional (ghqRootModule != null) ghqRootModule;

    config = {
      git.ghqRoot.enable = true;

      home-manager.sharedModules = lib.mkAfter [ mirrorModule ];
    };
  };
}
