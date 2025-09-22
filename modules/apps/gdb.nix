{
  flake.nixosModules.apps.gdb =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.gdb ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.gdb ];
    };
}
