{ lib, ... }:
{
  # mpv-only; orthogonal to the VA-API routing in nvidia-gpu.nix (mpv decodes
  # via FFmpeg NVCUVID, not libva). Carried over from system76, where
  # vo=gpu-next's default Vulkan backend deadlocks the GPU on render-context
  # churn (rapid playlist switching) and freezes the session; the GL backend
  # avoids it while keeping vo=gpu-next and profile=high-quality. Not yet
  # re-tested on the RTX 5080 with the open kernel modules: drop the override
  # once Vulkan proves stable here.
  configurations.nixos.songbird.module = {
    home-manager.sharedModules = [
      { programs.mpv.config.gpu-api = lib.mkDefault "opengl"; }
    ];
  };
}
