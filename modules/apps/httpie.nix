{
  flake.nixosModules.apps.httpie =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.httpie ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.httpie ];
    };
}
