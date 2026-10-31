/*
  Package: fzf
  Description: General-purpose command-line fuzzy finder for interactive filtering.
  Homepage: https://junegunn.github.io/fzf/
  Documentation: https://github.com/junegunn/fzf#usage
  Repository: https://github.com/junegunn/fzf

  Summary:
    * Filters lists with fuzzy search, multi-select, and previews.
    * Provides shell widgets so Ctrl-T, Ctrl-R, and custom bindings open interactive pickers.
*/
_:
let
  FzfModule =
    { lib, ... }:
    {
      options.programs.fzf.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable fzf.";
        };
      };
    };
in
{
  flake.nixosModules.apps.fzf = FzfModule;
}
