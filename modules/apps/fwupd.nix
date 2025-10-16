{
  flake.nixosModules.apps."fwupd" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.fwupd ];
    };
}
