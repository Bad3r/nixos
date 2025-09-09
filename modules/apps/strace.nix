{
  flake.modules.nixos.apps.strace =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.strace ];
    };
}
