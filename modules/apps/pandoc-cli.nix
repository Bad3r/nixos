{
  flake.nixosModules.apps."pandoc-cli" =
    { pkgs, ... }:
    {
      environment.systemPackages = [
        pkgs.haskellPackages."pandoc-cli"
      ];
    };
}
