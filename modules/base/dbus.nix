_: {
  flake.nixosModules.roles.system.base.imports = [
    (
      { pkgs, ... }:
      {
        services.dbus = {
          enable = true;
          packages = with pkgs; [ dconf ];
        };
      }
    )
  ];
}
