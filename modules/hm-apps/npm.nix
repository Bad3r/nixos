/*
  Package: npm
  Description: User-level npm defaults for the Nix-provided Node.js.
  Homepage: https://docs.npmjs.com/cli/using-npm/config
*/

_: {
  flake.homeManagerModules.apps.npm =
    {
      config,
      osConfig,
      lib,
      ...
    }:
    let
      nodeEnabled =
        lib.any (name: lib.attrByPath [ "programs" name "extended" "enable" ] false osConfig)
          [
            "nodejs_22"
            "nodejs_24"
          ];
      prefix = "${config.home.homeDirectory}/.npm-global";
    in
    {
      config = lib.mkIf nodeEnabled {
        # `npm install -g` cannot write to the store. Environment settings leave ~/.npmrc writable for `npm login`.
        home.sessionVariables = {
          NPM_CONFIG_PREFIX = prefix;
          NPM_CONFIG_CACHE = "${config.xdg.cacheHome}/npm";
          NPM_CONFIG_SAVE_EXACT = "true";
          NPM_CONFIG_ENGINE_STRICT = "true";
          NPM_CONFIG_AUDIT_LEVEL = "moderate";
          NPM_CONFIG_FUND = "false";
          NPM_CONFIG_UPDATE_NOTIFIER = "false";
          NPM_CONFIG_PROGRESS = "false";
        };
        home.sessionPath = [ "${prefix}/bin" ];

        # zsh only: a session-wide value would also reach every Electron app.
        programs.zsh.sessionVariables.NODE_OPTIONS = "--max-old-space-size=16384";
      };
    };
}
