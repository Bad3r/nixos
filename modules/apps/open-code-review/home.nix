/*
  Package: open-code-review
  Description: Home Manager glue for the Open Code Review config file and agent skills.
  Homepage: https://open-codereview.ai/
  Documentation: https://open-codereview.ai/docs
  Repository: https://github.com/alibaba/open-code-review

  Summary:
    * Renders ~/.opencodereview/config.json from programs.open-code-review.extended.settings.
    * Links the skills the package ships into Antigravity, Claude Code, and Codex on hosts that enable those apps.
*/
_: {
  flake.homeManagerModules.apps."open-code-review" =
    {
      osConfig,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = lib.attrByPath [ "programs" "open-code-review" "extended" ] { enable = false; } osConfig;
      appEnabled = name: lib.attrByPath [ "programs" name "extended" "enable" ] false osConfig;

      skillNames = [
        "open-code-review"
        "open-code-review-delegate"
      ];
      skillLinks =
        prefix: extra:
        lib.listToAttrs (
          map (
            name:
            lib.nameValuePair "${prefix}/${name}" (
              { source = "${cfg.package}/share/skills/open-code-review/${name}"; } // extra
            )
          ) skillNames
        );
    in
    {
      config = lib.mkIf cfg.enable {
        home.file = {
          ".opencodereview/config.json".source =
            (pkgs.formats.json { }).generate "open-code-review-config.json"
              cfg.settings;
        }
        // lib.optionalAttrs (appEnabled "antigravity-cli" || appEnabled "antigravity-hub") (
          skillLinks ".gemini/config/skills" { recursive = true; }
        )
        // lib.optionalAttrs (appEnabled "claude-code") (skillLinks ".claude/skills" { recursive = true; });

        xdg.configFile = lib.optionalAttrs (appEnabled "codex") (skillLinks "agents/skills" { });
      };
    };
}
