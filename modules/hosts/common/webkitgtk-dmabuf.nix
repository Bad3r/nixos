/*
  Internal: WebKitGTK DMABUF workaround for NVIDIA hosts
  Description: WebKitGTK's EGL/DMABUF zero-copy renderer corrupts surfaces on the
  NVIDIA proprietary driver under X11, the same root cause as the Gecko
  widget.dmabuf image corruption. Symptoms: Tauri apps (yaak) render a blank
  window; the WhatsApp-in-WebKitGTK client (karere) garbles its web surface.
  WebKitGTK honors WEBKIT_DISABLE_DMABUF_RENDERER=1 to fall back to a glReadPixels
  copy path; Gecko ignores this variable (it uses widget.dmabuf.enabled instead).

  Set as a session-wide environment variable, matching how the NVIDIA VA-API vars
  are wired in modules/system76/nvidia-gpu.nix, so launcher-started GTK apps
  inherit it. Gated on the NVIDIA proprietary X driver via
  services.xserver.videoDrivers so Intel/AMD hosts keep the zero-copy renderer.
*/
_:
let
  body =
    { config, lib, ... }:
    lib.mkIf (lib.elem "nvidia" config.services.xserver.videoDrivers) {
      environment.variables.WEBKIT_DISABLE_DMABUF_RENDERER = "1";
    };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
