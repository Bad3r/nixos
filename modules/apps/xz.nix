{
  flake.nixosModules.apps."xz" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.xz ];
    };
}
