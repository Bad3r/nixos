{
  flake.nixosModules.apps.forgit =
    { pkgs, lib, ... }:
    {
      environment.systemPackages = [ pkgs.zsh-forgit ];

      programs.zsh.interactiveShellInit = lib.mkAfter ''
        fpath+=(${pkgs.zsh-forgit}/share/zsh/site-functions)
        source ${pkgs.zsh-forgit}/share/zsh/zsh-forgit/forgit.plugin.zsh
      '';
    };
}
