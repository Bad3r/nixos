{
  flake.nixosModules.apps."ffmpeg-full" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.ffmpeg-full ];
    };
}
