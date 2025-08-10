# modules/editor.nix

{
  flake.modules.nixos.pc.programs = {
    neovim = {
      enable = true;
      vimAlias = true;
      viAlias = true;
      defaultEditor = true;
    };
    nano.enable = false;
  };
}
