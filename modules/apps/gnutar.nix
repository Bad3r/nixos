{
  flake.nixosModules.apps."gnutar" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.gnutar ];
    };
}
