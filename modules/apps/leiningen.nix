{
  flake.nixosModules.apps.leiningen =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.leiningen ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.leiningen ];
    };
}
