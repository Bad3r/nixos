{
  flake.nixosModules.apps.python =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.python312 ];
    };
}
