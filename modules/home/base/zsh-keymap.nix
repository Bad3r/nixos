
# modules/zsh-keymap.nix

{
  # Possible values:
  # emacs = "bindkey -e";
  # viins = "bindkey -v";
  # vicmd = "bindkey -a";
  flake.modules.homeManager.base.programs.zsh.defaultKeymap = "viins";

}
