{
  flake.nixosModules.apps.leiningen =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.leiningen ];
    };
}
