{
  flake.nixosModules.nvidia-gpu = _: {
    specialisation.nvidia-gpu.configuration = {
      services.xserver.videoDrivers = [ "nvidia" ];
    };
  };
}
