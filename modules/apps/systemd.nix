{
  flake.nixosModules.apps."systemd" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.systemd ];
    };
}
