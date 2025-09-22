{
  flake.nixosModules.apps.ddrescue =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.ddrescue ];
    };

  flake.nixosModules.base =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.ddrescue ];
    };
}
