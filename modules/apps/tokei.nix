{
  flake.nixosModules.apps.tokei =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.tokei ];
    };
}
