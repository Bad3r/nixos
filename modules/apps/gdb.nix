{
  flake.modules.nixos.apps.gdb =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.gdb ];
    };
}
