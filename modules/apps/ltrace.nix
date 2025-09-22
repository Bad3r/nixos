{
  flake.nixosModules.apps.ltrace =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.ltrace ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.ltrace ];
    };
}
