{
  flake.nixosModules.apps."udisks" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.udisks ];
    };
}
