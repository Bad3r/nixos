{
  flake.nixosModules.apps."tcpdump" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.tcpdump ];
    };
}
