{
  flake.modules.nixos.apps.hyperfine =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.hyperfine ];
    };
}
