{
  flake.nixosModules.apps.gnumake =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.gnumake ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.gnumake ];
    };
}
