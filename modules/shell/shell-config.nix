{
  flake.modules.nixos.base =
    { pkgs, ... }:
    {
      # Set dash as the default /bin/sh for better performance and POSIX compliance
      environment.binsh = "${pkgs.dash}/bin/dash";

      # Include dash in system packages
      environment.systemPackages = [ pkgs.dash ];
    };
}
