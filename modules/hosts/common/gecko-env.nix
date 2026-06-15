/*
  Gecko launch environment, migrated from dotfiles zsh startup
  (Bad3r/dotfiles config/zsh/rc.d/firefox.zsh).

  MOZ_X11_EGL selects the EGL GL backend on X11 and bypasses
  gfx.x11-egl.force-disabled, which VA-API decode depends on.

  Exported through sessionVariables (PAM-initialised) rather than variables
  (shell-profile only) so browsers started from the desktop/app menu inherit
  it, not just terminal-spawned ones.

  The dotfiles NVIDIA branch (NVD_BACKEND=direct, LIBVA_DRIVER_NAME=nvidia,
  MOZ_DISABLE_RDD_SANDBOX=1) is preserved only when the host installs
  nvidia-vaapi-driver. modules/system76/nvidia-gpu.nix deliberately rejects
  that driver: hardware.nvidia.videoAcceleration is false and VA-API routes
  through Intel iHD to avoid Xid 31 NVDEC faults, so the NVIDIA VA-API
  variables would override the host's iHD routing and weaken the RDD process
  sandbox for a decode path that does not exist.

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
        MOZ_DISABLE_RDD_SANDBOX = lib.mkDefault "1";
      };
    };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
