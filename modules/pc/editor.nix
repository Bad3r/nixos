{
  flake.nixosModules.pc = _: {
    programs.neovim = {
      enable = true;
      vimAlias = true;
      viAlias = true;
      defaultEditor = true;
    };
    programs.nano.enable = false;
  };
}
