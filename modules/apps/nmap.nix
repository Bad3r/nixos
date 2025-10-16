{
  flake.nixosModules.apps."nmap" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.nmap ];
    };
}
