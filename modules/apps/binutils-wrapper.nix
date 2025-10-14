{
  flake.nixosModules.apps."binutils-wrapper" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.binutils ];
    };
}
