{
  flake.nixosModules.apps.gnumake =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.gnumake ];
    };
}
