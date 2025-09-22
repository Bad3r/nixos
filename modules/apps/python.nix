{
  flake.nixosModules.apps.python =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.python312 ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.python312 ];
    };
}
