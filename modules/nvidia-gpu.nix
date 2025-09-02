{
  flake.modules.nixos.nvidia-gpu = _: {
    specialisation.nvidia-gpu.configuration = {
      services.xserver.videoDrivers = [ "nvidia" ];
    };
  };
}
