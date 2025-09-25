{
  config,
  ...
}:
{
  nixpkgs.allowedUnfreePackages = [ "coderabbit-cli" ];

  perSystem =
    { pkgs, ... }:
    {
      packages.coderabbit-cli = pkgs.callPackage ../../packages/coderabbit-cli { };
    };

  flake.nixosModules.apps.coderabbit-cli =
    { pkgs, ... }:
    {
      environment.systemPackages = [
        config.flake.packages.${pkgs.system}.coderabbit-cli
      ];
    };
}
