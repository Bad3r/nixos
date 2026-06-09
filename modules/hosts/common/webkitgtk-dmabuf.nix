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
