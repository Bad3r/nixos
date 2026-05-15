{
  flake.homeManagerModules.geckoSecrets =
    {
      lib,
      config,
      secretsRoot,
      ...
    }:
    let
      cfg = config.home.geckoSecrets;
      geckoFile = "${secretsRoot}/gecko.yaml";
      geckoFileExists = builtins.pathExists geckoFile;
      homeDirectory = config.home.homeDirectory;

      geckoBookmarks = import ../hm-apps/_gecko-bookmarks.nix { inherit lib; };

      secretKeys = {
        "gecko/work/bookmark/url-1" = "gecko_work_bookmark_url_1";
        "gecko/work/bookmark/url-2" = "gecko_work_bookmark_url_2";
        "gecko/work/bookmark/url-3" = "gecko_work_bookmark_url_3";
      };

      placeholder = name: config.sops.placeholder.${name};

      workBookmarkUrls = {
        deemMail = placeholder "gecko/work/bookmark/url-1";
        outlook = placeholder "gecko/work/bookmark/url-2";
        teams = placeholder "gecko/work/bookmark/url-3";
      };

      secretDeclarations = lib.mapAttrs (_: key: {
        sopsFile = geckoFile;
        inherit key;
      }) secretKeys;
    in
    {
      options.home.geckoSecrets.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to provision shared Gecko browser bookmark secrets.";
      };

      config = lib.mkMerge [
        (lib.mkIf (cfg.enable && geckoFileExists) {
          sops.secrets = secretDeclarations;

          sops.templates."gecko/bookmarks" = {
            path = "${homeDirectory}/.local/share/gecko/bookmarks.html";
            content = geckoBookmarks.html workBookmarkUrls;
            mode = "0600";
          };

          home.activation.ensureGeckoSecretDirs =
            lib.hm.dag.entryBetween [ "sops-nix" ] [ "writeBoundary" ]
              ''
                install -d -m 700 '${homeDirectory}/.local/share/gecko'
              '';
        })

        (lib.mkIf (cfg.enable && !geckoFileExists) {
          warnings = [
            "home.geckoSecrets.enable is true but ${geckoFile} is missing; skipping Gecko bookmark secrets."
          ];
        })
      ];
    };
}
