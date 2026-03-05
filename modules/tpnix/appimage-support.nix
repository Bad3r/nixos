{
  configurations.nixos.tpnix.module = {
    programs.appimage = {
      enable = true;
      binfmt = true;
    };
  };
}
