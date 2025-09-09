{
  flake.nixosModules.pc =
    { pkgs, ... }:
    {
      services.dbus = {
        enable = true;
        packages = with pkgs; [ dconf ];
      };
    };
}
