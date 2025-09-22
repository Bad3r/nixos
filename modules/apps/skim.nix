{
  flake.nixosModules.apps.skim =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.skim ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.skim ];
    };
}
