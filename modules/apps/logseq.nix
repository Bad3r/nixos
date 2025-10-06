{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      packages.logseq = inputs.nix-logseq-git-flake.packages.${pkgs.system}.logseq;
    };

  flake.nixosModules.apps.logseq =
    { config, lib, ... }:
    {
      environment.systemPackages = lib.mkDefault [
        inputs.nix-logseq-git-flake.packages.${config.system}.logseq
      ];
    };
}
