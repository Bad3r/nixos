{
  nixpkgs.allowedUnfreePackages = [ "temurin-bin-24" ];

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      config.environment.systemPackages = [ pkgs.temurin-bin-24 ];
    };
}
