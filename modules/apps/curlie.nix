{
  flake.modules.nixos.apps.curlie =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.curlie ];
    };
}
