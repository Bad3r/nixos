{
  flake.nixosModules.apps.hyperfine =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.hyperfine ];
    };
}
