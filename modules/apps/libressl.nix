{
  flake.nixosModules.apps."libressl" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.libressl ];
    };
}
