{
  flake.nixosModules.pc = {
    programs.neovim = {
      enable = true;
      vimAlias = true;
      viAlias = true;
      defaultEditor = true;
    };
    programs.nano.enable = false;
  };
}
