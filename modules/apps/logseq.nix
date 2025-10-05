{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      packages.logseq = inputs.nix-logseq-git-flake.packages.${pkgs.system}.logseq;
    };

  flake.nixosModules.apps.logseq = inputs.nix-logseq-git-flake.nixosModules.logseq;
}
