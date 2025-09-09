{
  flake.nixosModules.apps.gcc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.gcc ];
    };
}
