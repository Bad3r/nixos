{
  flake.nixosModules.apps."pkg-config-wrapper" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.pkg-config ];
    };
}
