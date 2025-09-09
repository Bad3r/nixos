{
  nixpkgs.allowedUnfreePackages = [ "temurin-bin-24" ];

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.temurin-bin-24 ];
    };
}
