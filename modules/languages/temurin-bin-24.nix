{
  nixpkgs.allowedUnfreePackages = [ "temurin-bin-24" ];

  flake.modules.nixos.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.temurin-bin-24 ];
    };
}
