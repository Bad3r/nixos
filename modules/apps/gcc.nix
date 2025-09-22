{
  flake.nixosModules.apps.gcc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.gcc ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.gcc ];
    };
}
