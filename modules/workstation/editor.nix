{ lib, ... }:
let
  editorModule = _: {
    programs.neovim = {
      enable = true;
      vimAlias = true;
      viAlias = true;
      defaultEditor = true;
    };
    programs.nano.enable = false;
  };
in
{
  flake.lib.roleExtras = lib.mkAfter [
    {
      role = "development.core";
      modules = [ editorModule ];
    }
  ];
}
