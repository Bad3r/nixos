{
  flake.nixosModules.apps.tokei =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.tokei ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.tokei ];
    };
}
