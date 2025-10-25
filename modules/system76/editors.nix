{
  configurations.nixos.system76.module = {
    programs.neovim = {
      enable = true;
      vimAlias = true;
      viAlias = true;
      defaultEditor = true;
    };

    programs.nano.enable = false;
  };
}
