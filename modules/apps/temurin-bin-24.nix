{
  nixpkgs.allowedUnfreePackages = [ "temurin-bin-24" ];
  flake.nixosModules.apps.temurin-bin-24 =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.temurin-bin-24 ];
    };
}
