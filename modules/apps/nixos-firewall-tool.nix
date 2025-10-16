{
  flake.nixosModules.apps."nixos-firewall-tool" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs."nixos-firewall-tool" ];
    };
}
