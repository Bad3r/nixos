{
  flake.modules.nixos.apps.wireguard-tools =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.wireguard-tools ];
    };
}
