{
  flake.nixosModules.apps."xauth" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.xorg.xauth ];
    };
}
