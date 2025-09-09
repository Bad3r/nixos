{
  flake.nixosModules.apps.babashka =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.babashka ];
    };
}
