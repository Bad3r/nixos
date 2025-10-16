{
  flake.nixosModules.apps."iceauth" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.xorg.iceauth ];
    };
}
