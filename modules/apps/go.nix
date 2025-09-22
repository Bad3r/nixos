{
  flake.nixosModules.apps.go =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.go ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.go ];
    };
}
