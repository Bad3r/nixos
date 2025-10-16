{
  flake.nixosModules.apps."dash" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.dash ];
    };
}
