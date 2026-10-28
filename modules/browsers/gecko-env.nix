/*
  Gecko launch environment, migrated from dotfiles zsh startup
  (Bad3r/dotfiles config/zsh/rc.d/firefox.zsh).

  MOZ_X11_EGL selects the EGL GL backend on X11 and bypasses
  gfx.x11-egl.force-disabled, which hardware video decode depends on.

  Exported through sessionVariables (PAM-initialised) rather than variables
  (shell-profile only) so browsers started from the desktop/app menu inherit
  it, not just terminal-spawned ones.

  The dotfiles NVIDIA branch (NVD_BACKEND=direct, LIBVA_DRIVER_NAME=nvidia) is
  preserved only when the host installs nvidia-vaapi-driver. A host on
  gpu.nvidia.vaapi.backend = "intel-media" (modules/hardware/nvidia-gpu.nix,
  see that option's Xid 31 rationale) never installs it, so the NVIDIA VA-API
  variables would override the host's iHD routing. Gecko itself cannot use the
  driver: nvidia-vaapi-driver declines to initialise in the sandboxed RDD
  process (vabackend.c), so the branch serves the session's other libva clients.

  No render-node variable accompanies LIBVA_DRIVER_NAME: libva 2.24 reads only
  LIBVA_DRIVER_NAME, LIBVA_DRIVERS_PATH, LIBVA_MESSAGING_LEVEL and LIBVA_TRACE*,
  and Gecko opens the render node of the EGL device it composes with (glxtest
  DRM_DEVICE), which MOZ_DRM_DEVICE overrides.

  On an NVIDIA host Gecko's hardware decode comes from gpu.intel.vulkanDecode,
  which moves it to the Intel iGPU through Vulkan (_gecko-mk-profile.nix
  withIgpuVideoDecode).

  WEBKIT_DISABLE_DMABUF_RENDERER from the same dotfiles branch is
  WebKit-specific and owned by modules/hosts/common/webkitgtk-dmabuf.nix.
*/
{ lib, ... }:
let
  body =
    { config, ... }:
    let
      hasNvidiaVaapiDriver = builtins.any (
        package: lib.getName package == "nvidia-vaapi-driver"
      ) config.hardware.graphics.extraPackages;
    in
    {
      environment.sessionVariables = {
        MOZ_X11_EGL = "1";
      }
      // lib.optionalAttrs hasNvidiaVaapiDriver {
        NVD_BACKEND = lib.mkDefault "direct";
        LIBVA_DRIVER_NAME = lib.mkDefault "nvidia";
      };
    };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
