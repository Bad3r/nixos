{ lib, ... }:
{
  # mpv-only; orthogonal to the VA-API -> iHD change in nvidia-gpu.nix (mpv decodes
  # via FFmpeg NVCUVID, not libva). vo=gpu-next's default Vulkan backend deadlocks the
  # GPU on render-context churn (rapid playlist switching), freezing the session; the
  # GL backend avoids it while keeping vo=gpu-next and profile=high-quality.
  configurations.nixos.system76.module = {
    home-manager.sharedModules = [
      { programs.mpv.config.gpu-api = lib.mkDefault "opengl"; }
    ];
  };
}
