{
  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      config.environment.systemPackages = [ pkgs.pkg-config ];
    };
}
