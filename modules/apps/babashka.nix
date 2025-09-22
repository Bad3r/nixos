{
  flake.nixosModules.apps.babashka =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.babashka ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.babashka ];
    };
}
