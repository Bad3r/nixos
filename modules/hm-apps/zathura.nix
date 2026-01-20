/*
  Package: zathura
  Description: Highly customizable and functional document viewer.
  Homepage: https://pwmt.org/projects/zathura
  Documentation: https://pwmt.org/projects/zathura/documentation
  Repository: https://github.com/pwmt/zathura

  Summary:
    * Supports multiple document formats (PDF, PostScript, DjVu) via plugin system.
    * Features vim-like keybindings, bookmarks, SyncTeX support, and customizable interface.

  Options:
    -c: Path to the config directory.
    -d: Path to the data directory.
    -p: Path to the directory containing plugins.
    -w: Specify document password for encrypted files.
    -P: Open document at specified page number.
    -f: Open document and search for given string.
    -l: Set log level (debug, info, warning, error).
    -x: Set the synctex editor command.
    --mode: Start in a non-default mode.
    --fork: Fork into background.
*/

_: {
  flake.homeManagerModules.apps.zathura =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "zathura" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        programs.zathura.enable = true;
      };
    };
}
