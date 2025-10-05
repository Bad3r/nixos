{
  config,
  lib,
  ...
}:
let
  owner = config.flake.lib.meta.owner.username;
  ghqRootModule =
    let
      nixosModules = (config.flake or { }).nixosModules or { };
    in
    lib.attrByPath [ "git" "ghq-root" ] null nixosModules;
  mirrorRepos = [
    "NixOS/nixpkgs"
    "NixOS/nixos-hardware"
    "nix-community/home-manager"
    "nix-community/stylix"
    "nix-community/nixvim"
    "logseq/logseq"
    "cachix/git-hooks.nix"
    "mightyiam/files"
    "Mic92/sops-nix"
    "numtide/treefmt-nix"
    "vic/import-tree"
  ];
in
{
  configurations.nixos.system76.module =
    { lib, ... }:
    let
      gitCfg = lib.optionalAttrs (ghqRootModule != null) {
        git.ghqRoot.enable = true;
      };
    in
    {
      imports = lib.optional (ghqRootModule != null) ghqRootModule;

      home-manager.users.${owner} = {
        programs.ghqMirror.repos = lib.mkForce mirrorRepos;

      };
    }
    // gitCfg;
}
