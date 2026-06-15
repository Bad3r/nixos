_:
let
  body =
    { config, lib, ... }:
    lib.mkIf (lib.elem "nvidia" config.services.xserver.videoDrivers) {
      # sessionVariables (PAM-initialised) so launcher-started GTK apps inherit
      # the DMABUF-renderer disable, not just shell-spawned ones.
      environment.sessionVariables.WEBKIT_DISABLE_DMABUF_RENDERER = "1";
    };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
