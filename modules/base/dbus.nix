{
  flake.modules.nixos.pc = { pkgs, ... }: {
    services.dbus = {
      enable = true;
      packages = with pkgs; [ dconf ];
    };
  };
}