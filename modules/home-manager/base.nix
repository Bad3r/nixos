_: {
  flake.homeManagerModules.base = {
    home.preferXdgDirectories = true;
    programs.home-manager.enable = true;
    systemd.user.startServices = "sd-switch";
  };
}
