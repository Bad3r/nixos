{
  flake.modules.nixos.nvidia-gpu =
    { pkgs, ... }:
    {
      specialisation.nvidia-gpu.configuration = {
        services.xserver.videoDrivers = [ "nvidia" ];
      };
    };
}
