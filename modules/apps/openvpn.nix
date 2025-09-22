{
  flake.nixosModules.apps.openvpn =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.openvpn ];
    };

  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.openvpn ];
    };
}
