{
  flake.nixosModules.apps.strace =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.strace ];
    };
}
