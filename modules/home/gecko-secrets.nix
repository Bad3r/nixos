{
  flake.homeManagerModules.geckoSecrets =
    {
      lib,
      config,
      metaOwner,
      secretsRoot,
      ...
    }:
    let
      cfg = config.home.geckoSecrets;
      geckoFile = "${secretsRoot}/gecko.yaml";
      geckoFileExists = builtins.pathExists geckoFile;
      homeDirectory = "/home/${metaOwner.username}";

      geckoBookmarks = import ../hm-apps/_gecko-bookmarks.nix { inherit lib; };

      secretKeys = {
        "gecko/work/bookmark/url-1" = "gecko_work_bookmark_url_1";
        "gecko/work/bookmark/url-2" = "gecko_work_bookmark_url_2";
        "gecko/work/bookmark/url-3" = "gecko_work_bookmark_url_3";
        "gecko/work/assignment/host-1" = "gecko_work_assignment_host_1";
        "gecko/work/assignment/host-2" = "gecko_work_assignment_host_2";
        "gecko/work/assignment/host-3" = "gecko_work_assignment_host_3";
        "gecko/work/assignment/host-4" = "gecko_work_assignment_host_4";
        "gecko/work/assignment/host-5" = "gecko_work_assignment_host_5";
        "gecko/work/assignment/host-6" = "gecko_work_assignment_host_6";
        "gecko/work/assignment/host-7" = "gecko_work_assignment_host_7";
        "gecko/work/assignment/host-8" = "gecko_work_assignment_host_8";
      };

      placeholder = name: config.sops.placeholder.${name};

      workBookmarkUrls = {
        deemMail = placeholder "gecko/work/bookmark/url-1";
        outlook = placeholder "gecko/work/bookmark/url-2";
        teams = placeholder "gecko/work/bookmark/url-3";
      };

      siteAssignment = userContextId: {
        inherit userContextId;
        neverAsk = false;
      };

      nonWorkSiteAssignments = {
        "siteContainerMap@@_github.com" = siteAssignment "5";
        "siteContainerMap@@_octobox.io" = siteAssignment "5";
        "siteContainerMap@@_accounts.google.com" = siteAssignment "2";
        "siteContainerMap@@_music.youtube.com" = siteAssignment "2";
        "siteContainerMap@@_notebooklm.google.com" = siteAssignment "2";
        "siteContainerMap@@_www.google.com" = siteAssignment "2";
        "siteContainerMap@@_www.youtube.com" = siteAssignment "2";
        "siteContainerMap@@_web.whatsapp.com" = siteAssignment "4";
        "siteContainerMap@@_webtp.whatsapp.net" = siteAssignment "4";
      };

      workSiteAssignments = builtins.listToAttrs (
        map (name: lib.nameValuePair "siteContainerMap@@_${placeholder name}" (siteAssignment "1")) [
          "gecko/work/assignment/host-1"
          "gecko/work/assignment/host-2"
          "gecko/work/assignment/host-3"
          "gecko/work/assignment/host-4"
          "gecko/work/assignment/host-5"
          "gecko/work/assignment/host-6"
          "gecko/work/assignment/host-7"
          "gecko/work/assignment/host-8"
        ]
      );

      multiAccountContainersStorage = builtins.toJSON (nonWorkSiteAssignments // workSiteAssignments);

      profileNames = [
        "primary"
        "work"
        "ephemeral"
      ];

      browsers = [
        "firefox"
        "floorp"
        "librewolf"
      ];

      browserEnabled = browser: lib.attrByPath [ "programs" browser "enable" ] false config;
      browserProfilesPath =
        browser: lib.attrByPath [ "programs" browser "profilesPath" ] ".${browser}" config;
      profilePath =
        browser: profile:
        lib.attrByPath [
          "programs"
          browser
          "profiles"
          profile
          "path"
        ] profile config;

      enabledTargets = lib.flatten (
        map (
          browser:
          lib.optionals (browserEnabled browser) (
            map (profile: {
              inherit browser profile;
              profilesPath = browserProfilesPath browser;
              path = profilePath browser profile;
            }) profileNames
          )
        ) browsers
      );

      storageDir =
        target:
        "${homeDirectory}/${target.profilesPath}/${target.path}/browser-extension-data/@testpilot-containers";
      storagePath = target: "${storageDir target}/storage.js";

      storageTemplates = builtins.listToAttrs (
        map (
          target:
          lib.nameValuePair "gecko/${target.browser}/${target.profile}/multi-account-containers" {
            path = storagePath target;
            content = multiAccountContainersStorage;
            mode = "0600";
          }
        ) enabledTargets
      );

      secretDeclarations = lib.mapAttrs (_: key: {
        sopsFile = geckoFile;
        inherit key;
      }) secretKeys;
    in
    {
      options.home.geckoSecrets.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to provision shared Gecko browser bookmarks and container assignment secrets.";
      };

      config = lib.mkMerge [
        (lib.mkIf (cfg.enable && geckoFileExists) {
          sops.secrets = secretDeclarations;

          sops.templates = {
            "gecko/bookmarks" = {
              path = "${homeDirectory}/.local/share/gecko/bookmarks.html";
              content = geckoBookmarks.html workBookmarkUrls;
              mode = "0600";
            };
          }
          // storageTemplates;

          home.activation.ensureGeckoSecretDirs =
            lib.hm.dag.entryBetween [ "sops-nix" ] [ "writeBoundary" ]
              ''
                install -d -m 700 '${homeDirectory}/.local/share/gecko'
                ${lib.concatMapStringsSep "\n" (target: "install -d -m 700 '${storageDir target}'") enabledTargets}
              '';
        })

        (lib.mkIf (cfg.enable && !geckoFileExists) {
          warnings = [
            "home.geckoSecrets.enable is true but ${geckoFile} is missing; skipping Gecko bookmark and container-assignment secrets."
          ];
        })
      ];
    };
}
