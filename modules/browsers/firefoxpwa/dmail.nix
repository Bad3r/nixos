/*
  firefoxpwa: DMail web app
  Description: Installs the primary user's work mail site as a standalone
    Progressive Web App through the firefoxpwa CLI. The start URL is never
    written to the Nix store: it is read at runtime from the SOPS-encrypted
    work-bookmark secret that modules/home/gecko-secrets.nix already stores
    (gecko.yaml key gecko_work_bookmark_url_1).

  Mechanism:
    * A oneshot user service ordered after sops-nix.service decrypts the URL and
      runs `firefoxpwa site install` with a synthetic data: manifest, so the
      site installs without the target having to serve a web manifest.
    * The install is idempotent: a site already carrying the managed name is
      refreshed in place when the decrypted URL has rotated and otherwise left
      untouched, so the service is safe to run on every login. Rotation is
      detected against a dmail-applied-url marker written next to config.json.
    * firefoxpwa system integration writes the launcher .desktop entry and icon,
      making the app discoverable from the desktop menu.
*/
_: {
  flake.homeManagerModules.firefoxpwaDmail =
    {
      config,
      lib,
      pkgs,
      osConfig,
      secretsRoot,
      ...
    }:
    let
      geckoFile = secretsRoot + "/gecko.yaml";
      geckoFileExists = builtins.pathExists geckoFile;

      # Per-host toggle declared at NixOS scope in ./apps.nix; layered by the
      # common app catalog (off) and modules/tpnix/apps-enable.nix (on).
      dmailEnabled = osConfig.programs.firefoxpwa.dmail.enable or false;
      firefoxpwaEnabled = osConfig.programs.firefoxpwa.extended.enable or false;
      firefoxpwaPackage = osConfig.programs.firefoxpwa.extended.package or pkgs.firefoxpwa;

      secretName = "firefoxpwa/dmail/url";
      urlPath = config.sops.secrets.${secretName}.path or null;

      # The launcher name doubles as the idempotency key. firefoxpwa stores it in
      # config.json at .sites.<ulid>.config.name, so an existing site with this
      # name means the app is already installed.
      appName = "DMail";

      installScript = pkgs.writeShellApplication {
        name = "firefoxpwa-install-dmail";
        runtimeInputs = [
          firefoxpwaPackage
          pkgs.jq
          pkgs.coreutils
        ];
        text = ''
          url_file=${lib.escapeShellArg urlPath}
          app_name=${lib.escapeShellArg appName}
          data_dir="''${XDG_DATA_HOME:-$HOME/.local/share}/firefoxpwa"
          config_file="$data_dir/config.json"

          # firefoxpwa deserializes start_url into the Rust url crate's Url
          # (native/src/components/site.rs) and serde writes back its normalized
          # form, so config.json can hold https://host/ for a secret that reads
          # https://host. Comparing against a marker this script writes keeps the
          # idempotency check byte-exact instead of racing that normalization.
          applied_file="$data_dir/dmail-applied-url"

          if [ ! -r "$url_file" ]; then
            echo "firefoxpwa-dmail: secret not readable at $url_file" >&2
            exit 1
          fi

          url=$(<"$url_file")
          url="''${url//[[:space:]]/}"
          if [ -z "$url" ]; then
            echo "firefoxpwa-dmail: decrypted URL is empty" >&2
            exit 1
          fi

          # firefoxpwa stores the managed site under .sites.<ulid> and the
          # launcher name set with --name lands at .config.name, so a site
          # carrying this name is our install. Emits the ulid, or nothing.
          # Taking the first match inside jq keeps the exit status jq's own:
          # piping to `head -n1` lets head close the pipe first and SIGPIPE jq,
          # which pipefail then reports as failure.
          site_ulid() {
            [ -f "$config_file" ] || return 0
            jq -r --arg n "$app_name" \
              'first((.sites // {}) | to_entries[] | select(.value.config.name == $n) | .key) // empty' \
              "$config_file" 2>/dev/null
          }

          # scope is web_app_manifest's Url enum, which is #[serde(untagged)], so
          # it lands in config.json as a plain string (or null when unresolved).
          site_scope() {
            jq -r --arg i "$1" '.sites[$i].manifest.scope // empty' \
              "$config_file" 2>/dev/null
          }

          # RFC 3986 3.1: the scheme is case-insensitive, and the authority ends
          # at the first /, ? or #. Emits the origin, or nothing.
          url_origin() {
            [[ $1 =~ ^([A-Za-z][A-Za-z0-9+.-]*://[^/?#]+) ]] || return 0
            printf '%s' "''${BASH_REMATCH[1]}"
          }

          # The marker holds the decrypted secret, so it is created owner-only.
          record_applied() {
            (
              umask 077
              printf '%s' "$url" >"$applied_file"
            )
          }

          # Manifest scope is a prefix match and site update cannot rewrite it,
          # so it must be the bare origin: anything longer pushes same-origin
          # navigation and every later URL rotation into the external browser.
          origin=$(url_origin "$url")
          if [ -z "$origin" ]; then
            echo "firefoxpwa-dmail: cannot derive an origin from '$url'" >&2
            exit 1
          fi

          # Already installed. The start URL is read at runtime from the rotating
          # secret, so refresh it in place when the marker drifts instead of
          # leaving the app pinned to the URL captured at first install. A site
          # installed before the marker existed takes one refresh, then no-ops.
          if ulid=$(site_ulid) && [ -n "$ulid" ]; then
            if [ -r "$applied_file" ] && [ "$(<"$applied_file")" = "$url" ]; then
              echo "firefoxpwa-dmail: '$app_name' already installed with current URL"
              exit 0
            fi

            # A rotation that crosses to a new origin cannot be applied: scope is
            # fixed at install time, so the new start URL would sit outside it and
            # every navigation would go to the external browser. Refuse loudly
            # rather than let record_applied mark that state as current. Compared
            # case-insensitively because the url crate lowercases the stored scope
            # while the secret keeps whatever case it was written in.
            if ! scope=$(site_scope "$ulid"); then
              echo "firefoxpwa-dmail: cannot read the installed scope for '$app_name' ($ulid)" >&2
              exit 1
            fi
            scope_origin=$(url_origin "$scope")
            if [ -n "$scope_origin" ] && [ "''${scope_origin,,}" != "''${origin,,}" ]; then
              echo "firefoxpwa-dmail: rotated URL origin '$origin' is outside the installed scope '$scope'; uninstall the '$app_name' site to let this unit reinstall it" >&2
              exit 1
            fi

            echo "firefoxpwa-dmail: refreshing start URL for '$app_name' ($ulid)"
            if firefoxpwa site update "$ulid" --start-url "$url" --no-manifest-updates; then
              record_applied
              echo "firefoxpwa-dmail: updated start URL for '$app_name'"
              exit 0
            fi
            echo "firefoxpwa-dmail: failed to update start URL for '$app_name'" >&2
            exit 1
          fi

          # A data: manifest keeps the install self-contained: firefoxpwa does not
          # have to fetch or parse a manifest from the target site. --document-url
          # is required whenever the manifest URL is a data: URL.
          manifest=$(jq -nc --arg u "$url" --arg s "$origin" --arg n "$app_name" \
            '{name: $n, scope: $s, start_url: $u, display: "standalone"}')
          manifest_url="data:application/manifest+json;base64,$(printf '%s' "$manifest" | base64 -w0)"

          for attempt in 1 2 3; do
            if firefoxpwa site install "$manifest_url" \
              --document-url "$url" \
              --start-url "$url" \
              --name "$app_name"; then
              record_applied
              echo "firefoxpwa-dmail: installed '$app_name'"
              exit 0
            fi
            # A failed attempt can still register the site before erroring (for
            # example on desktop integration); re-checking the name keeps the
            # retry from creating a second "DMail" entry.
            if ulid=$(site_ulid) && [ -n "$ulid" ]; then
              record_applied
              echo "firefoxpwa-dmail: '$app_name' registered despite a failed attempt; not retrying"
              exit 0
            fi
            echo "firefoxpwa-dmail: install attempt $attempt failed; retrying" >&2
            sleep 5
          done

          echo "firefoxpwa-dmail: install failed after 3 attempts" >&2
          exit 1
        '';
      };
    in
    {
      config = lib.mkMerge [
        (lib.mkIf (dmailEnabled && firefoxpwaEnabled && geckoFileExists) {
          sops.secrets.${secretName} = {
            sopsFile = geckoFile;
            key = "gecko_work_bookmark_url_1";
            path = "${config.home.homeDirectory}/.local/share/firefoxpwa/dmail-url";
            mode = "0400";
          };

          systemd.user.services.firefoxpwa-dmail = {
            Unit = {
              Description = "Install the DMail web app (firefoxpwa)";
              After = [ "sops-nix.service" ];
              Wants = [ "sops-nix.service" ];
              # RemainAfterExit leaves the unit active, so nothing would restart
              # it after a rotation: its own text does not change. sops-nix's
              # Home Manager activation always runs `systemctl restart --user
              # sops-nix`, so binding to that unit is what makes the refresh
              # branch reachable on switch rather than only at next login.
              PartOf = [ "sops-nix.service" ];
            };
            Service = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = lib.getExe installScript;
            };
            Install.WantedBy = [
              "default.target"
              "sops-nix.service"
            ];
          };
        })

        (lib.mkIf (dmailEnabled && firefoxpwaEnabled && !geckoFileExists) {
          warnings = [
            "programs.firefoxpwa.dmail.enable is true but ${toString geckoFile} is missing; skipping the DMail PWA install."
          ];
        })

        (lib.mkIf (dmailEnabled && !firefoxpwaEnabled) {
          warnings = [
            "programs.firefoxpwa.dmail.enable is true but programs.firefoxpwa.extended.enable is false; skipping the DMail PWA install."
          ];
        })
      ];
    };
}
