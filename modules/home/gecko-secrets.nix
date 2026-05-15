{
  flake.homeManagerModules.geckoSecrets =
    {
      lib,
      config,
      pkgs,
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
        "pentesting"
        "work"
      ];

      browsers = [
        "firefox"
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

      assignmentRoot = "${homeDirectory}/.local/share/gecko/container-assignments";
      assignmentDir = target: "${assignmentRoot}/${target.browser}";
      assignmentPath = target: "${assignmentDir target}/${target.profile}.json";

      assignmentTemplates = builtins.listToAttrs (
        map (
          target:
          lib.nameValuePair "gecko/${target.browser}/${target.profile}/multi-account-containers" {
            path = assignmentPath target;
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
          // assignmentTemplates;

          home.activation.ensureGeckoSecretDirs =
            lib.hm.dag.entryBetween [ "sops-nix" ] [ "writeBoundary" ]
              ''
                install -d -m 700 '${homeDirectory}/.local/share/gecko'
                ${lib.concatMapStringsSep "\n" (target: ''
                  install -d -m 700 '${assignmentDir target}'
                  install -d -m 700 '${storageDir target}'
                '') enabledTargets}
              '';

          # Multi-Account Containers rewrites storage.js at runtime, so keep
          # the secret source outside the profile and merge declared assignments
          # into the browser-owned file after sops-nix renders templates.
          home.activation.applyGeckoContainerAssignments = lib.hm.dag.entryAfter [ "sops-nix" ] ''
            merge_gecko_container_assignments() {
              assignment_path="$1"
              storage_dir="$2"
              storage_path="$storage_dir/storage.js"
              tmp_existing="$(mktemp)"
              tmp_merged="$(mktemp)"

              if [ ! -r "$assignment_path" ]; then
                echo "ERROR: missing Gecko container assignment file: $assignment_path" >&2
                rm -f "$tmp_existing" "$tmp_merged"
                exit 1
              fi

              install -d -m 700 "$storage_dir"

              if [ -e "$storage_path" ]; then
                existing_path="$storage_path"
              else
                printf '{}\n' > "$tmp_existing"
                existing_path="$tmp_existing"
              fi

              if ! ${pkgs.jq}/bin/jq -S -s '
                if (.[0] | type) != "object" then
                  error("existing Gecko container storage is not a JSON object")
                elif (.[1] | type) != "object" then
                  error("declared Gecko container assignments are not a JSON object")
                else
                  .[0] * .[1]
                end
              ' "$existing_path" "$assignment_path" > "$tmp_merged"; then
                echo "ERROR: failed to merge Gecko container assignments into $storage_path" >&2
                rm -f "$tmp_existing" "$tmp_merged"
                exit 1
              fi

              mv "$tmp_merged" "$storage_path"
              chmod 600 "$storage_path"
              rm -f "$tmp_existing"
            }

            ${lib.concatMapStringsSep "\n" (
              target: "merge_gecko_container_assignments '${assignmentPath target}' '${storageDir target}'"
            ) enabledTargets}
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
