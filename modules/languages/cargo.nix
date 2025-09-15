{
  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      config.environment.systemPackages = [ pkgs.cargo ];
    };
}
