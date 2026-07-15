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
    * The install is idempotent: it is skipped when a firefoxpwa site already
      carries the managed name, so the service is safe to run on every login.
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
          config_file="''${XDG_DATA_HOME:-$HOME/.local/share}/firefoxpwa/config.json"

          if [ ! -r "$url_file" ]; then
            echo "firefoxpwa-dmail: secret not readable at $url_file" >&2
            exit 1
          fi

          url=$(tr -d '[:space:]' < "$url_file")
          if [ -z "$url" ]; then
            echo "firefoxpwa-dmail: decrypted URL is empty" >&2
            exit 1
          fi

          if [ -f "$config_file" ] \
            && jq -e --arg n "$app_name" \
              '(.sites // {}) | to_entries[] | select(.value.config.name == $n)' \
              "$config_file" >/dev/null 2>&1; then
            echo "firefoxpwa-dmail: '$app_name' already installed"
            exit 0
          fi

          # A data: manifest keeps the install self-contained: firefoxpwa does not
          # have to fetch or parse a manifest from the target site. --document-url
          # is required whenever the manifest URL is a data: URL.
          manifest=$(jq -nc --arg u "$url" --arg n "$app_name" \
            '{name: $n, scope: $u, start_url: $u, display: "standalone"}')
          manifest_url="data:application/manifest+json;base64,$(printf '%s' "$manifest" | base64 -w0)"

          for attempt in 1 2 3; do
            if firefoxpwa site install "$manifest_url" \
              --document-url "$url" \
              --start-url "$url" \
              --name "$app_name"; then
              echo "firefoxpwa-dmail: installed '$app_name'"
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
            };
            Service = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = lib.getExe installScript;
            };
            Install.WantedBy = [ "default.target" ];
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
