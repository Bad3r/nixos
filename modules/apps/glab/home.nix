_: {
  flake.homeManagerModules.apps.glab =
    { osConfig, lib, ... }:
    let
      cfg = lib.attrByPath [ "programs" "glab" "extended" ] { enable = false; } osConfig;
    in
    {
      # Declared here because `glab auth login` cannot write the read-only git config.
      config = lib.mkIf cfg.enable {
        programs.git.settings.credential."https://gitlab.com".helper = [
          ""
          "!${lib.getExe cfg.package} auth git-credential"
        ];
      };
    };
}
