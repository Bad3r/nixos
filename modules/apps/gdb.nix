{
  flake.nixosModules.apps.gdb =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.gdb ];
    };
}
