{
  flake.nixosModules.apps.wireguard-tools =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.wireguard-tools ];
    };
}
