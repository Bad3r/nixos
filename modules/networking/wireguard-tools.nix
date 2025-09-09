{
  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.wireguard-tools ];
    };
}
