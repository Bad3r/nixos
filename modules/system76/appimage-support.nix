{
  configurations.nixos.system76.module = {
    programs.appimage = {
      enable = true;
      binfmt = true;
    };
  };
}
