{
  flake.nixosModules.apps."ffmpegthumbnailer" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.ffmpegthumbnailer ];
    };
}
