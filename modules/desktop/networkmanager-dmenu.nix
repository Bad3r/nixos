{
  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.networkmanager_dmenu ];
    };
}
