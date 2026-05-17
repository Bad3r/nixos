_:
let
  body = {
    services.pipewire = {
      enable = true;
      alsa = {
        enable = true;
        support32Bit = true;
      };
      pulse.enable = true;
    };

    security.rtkit.enable = true;
  };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
