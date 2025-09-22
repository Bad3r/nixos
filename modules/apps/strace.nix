{
  flake.nixosModules.apps.strace =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.strace ];
    };

  flake.nixosModules.workstation =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.strace ];
    };
}
