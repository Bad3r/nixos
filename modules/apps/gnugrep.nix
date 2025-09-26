{
  flake.nixosModules.apps.gnugrep =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.gnugrep ];
    };
}
