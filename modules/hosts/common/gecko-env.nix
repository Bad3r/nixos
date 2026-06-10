/*
  Gecko launch environment, migrated from dotfiles zsh startup
  (Bad3r/dotfiles config/zsh/rc.d/firefox.zsh).

  MOZ_X11_EGL selects the EGL GL backend on X11 and bypasses
  gfx.x11-egl.force-disabled, which VA-API decode depends on; see the
  widget.dmabuf note in modules/hm-apps/_gecko-prefs.nix.

  The dotfiles NVIDIA branch (NVD_BACKEND=direct, LIBVA_DRIVER_NAME=nvidia,
  MOZ_DISABLE_RDD_SANDBOX=1) is intentionally not ported. Those variables
  configure nvidia-vaapi-driver, which modules/system76/nvidia-gpu.nix
  deliberately rejects: hardware.nvidia.videoAcceleration is false and
  VA-API routes through Intel iHD to avoid Xid 31 NVDEC faults, so
  LIBVA_DRIVER_NAME=nvidia would point libva at an uninstalled driver and
  override the host's iHD routing, while MOZ_DISABLE_RDD_SANDBOX would
  weaken the RDD process sandbox for a decode path that does not exist.

  WEBKIT_DISABLE_DMABUF_RENDERER from the same dotfiles branch is
  WebKit-specific and owned by modules/hosts/common/webkitgtk-dmabuf.nix.
*/
_:
let
  body = {
    environment.variables = {
      MOZ_X11_EGL = "1";
    };
  };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
