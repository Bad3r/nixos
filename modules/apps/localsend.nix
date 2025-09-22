{
  flake.nixosModules.apps.localsend =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.localsend ];
    };

  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.localsend ];
    };
}
