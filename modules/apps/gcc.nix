{
  flake.modules.nixos.apps.gcc =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.gcc ];
    };
}
