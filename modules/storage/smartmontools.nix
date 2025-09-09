{
  flake.nixosModules.base =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.smartmontools ];

      services.smartd = {
        enable = true;
        notifications = {
          x11.enable = true;
          wall.enable = true;
        };
      };
    };
}
