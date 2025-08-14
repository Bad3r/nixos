{
  flake.modules.nixos.base = { pkgs, ... }: {
    environment.binsh = "${pkgs.dash}/bin/dash";
    programs.zsh.enable = true;
    users.mutableUsers = true;
    users.defaultUserShell = pkgs.zsh;
  };
}