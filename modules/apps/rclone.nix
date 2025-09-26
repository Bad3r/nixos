{
  flake.nixosModules.apps.rclone =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.rclone ];
    };
}
