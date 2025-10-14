{
  flake.nixosModules.apps."cryptsetup" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.cryptsetup ];
    };
}
