{
  flake.nixosModules.apps.curlie =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.curlie ];
    };
}
