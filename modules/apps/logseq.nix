{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      packages.logseq = inputs.nix-logseq-git-flake.packages.${pkgs.system}.logseq;
    };

  flake.nixosModules.apps.logseq =
    {
      lib,
      pkgs,
      ...
    }:
    {
      environment.systemPackages = lib.mkAfter [
        inputs.nix-logseq-git-flake.packages.${pkgs.system}.logseq
      ];
    };
}
