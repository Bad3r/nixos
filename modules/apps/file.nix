{
  flake.nixosModules.apps.file =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.file ];
    };
}
