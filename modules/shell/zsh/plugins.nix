{
  flake.homeManagerModules.zsh =
    {
      config,
      lib,
      osConfig,
      pkgs,
      ...
    }:
    let
      forgitCfg = lib.attrByPath [ "programs" "forgit" "extended" ] { enable = false; } osConfig;

      # Standalone plugin files; the oh-my-zsh framework itself is not loaded.
      omzDir = "${pkgs.oh-my-zsh}/share/oh-my-zsh/plugins";
      omzPlugins = [
        "extract"
        "fancy-ctrl-z"
        "last-working-dir"
        "sudo"
        "systemd"
        "universalarchive"
      ];
      # These ship a completion function next to the plugin file.
      omzCompletionDirs = map (name: "${omzDir}/${name}") [
        "extract"
        "universalarchive"
      ];
    in
    {
      programs.zsh = {
        autosuggestion.enable = true;
        fastSyntaxHighlighting.enable = true;

        # last-working-dir keeps its state file here.
        localVariables.ZSH_CACHE_DIR = "${config.xdg.cacheHome}/zsh";

        initContent = lib.mkMerge [
          (lib.mkOrder 550 ''
            fpath+=(${lib.concatStringsSep " " omzCompletionDirs})
          '')

          (lib.mkOrder 900 ''
            source ${pkgs.zsh-autopair}/share/zsh/zsh-autopair/autopair.zsh
            ${lib.concatMapStringsSep "\n" (name: "source ${omzDir}/${name}/${name}.plugin.zsh") omzPlugins}
          '')

          # After aliases (1100): forgit's ga, gd, gco and friends replace the plain git ones.
          (lib.mkIf forgitCfg.enable (
            lib.mkOrder 1150 ''
              source ${forgitCfg.package}/share/zsh/zsh-forgit/forgit.plugin.zsh
            ''
          ))
        ];
      };
    };
}
