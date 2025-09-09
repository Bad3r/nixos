{
  flake.modules.nixos.apps.leiningen =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.leiningen ];
    };
}
