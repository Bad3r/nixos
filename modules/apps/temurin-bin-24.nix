{
  nixpkgs.allowedUnfreePackages = [ "temurin-bin-24" ];

  flake.nixosModules.apps."temurin-bin-24" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.temurin-bin-24 ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.temurin-bin-24 ];
    };
}
