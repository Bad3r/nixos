{
  flake.nixosModules.apps."iptables" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.iptables ];
    };
}
