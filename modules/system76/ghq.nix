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
      overrideModule =
        { lib, options, ... }:
        lib.mkIf (lib.hasAttrByPath [ "apps" "logseq" "runOnActivation" ] options) {
          apps.logseq.runOnActivation = lib.mkForce false;
        };

      importsList = lib.optional (ghqRootModule != null) ghqRootModule ++ [ overrideModule ];

      gitCfg = lib.optionalAttrs (ghqRootModule != null) {
        git.ghqRoot.enable = true;
      };
    in
    {
      imports = importsList;

      home-manager.users.${owner} = {
        programs.ghqMirror.repos = lib.mkForce mirrorRepos;

      };
    }
    // gitCfg;
}
