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

      # Single source for the secret, the marker, firefoxpwa's config.json and
      # the 0700 hardening below. Derived twice they drift apart as soon as
      # xdg.dataHome moves, leaving the two files that hold the decrypted URL
      # outside the directory the hardening applies to.
      dataDir = "${config.xdg.dataHome}/firefoxpwa";

      installScript = (pkgs.callPackage ../../../packages/firefoxpwa-dmail-install { }) {
        firefoxpwa = firefoxpwaPackage;
        inherit urlPath dataDir appName;
      };
    in
    {
      config = lib.mkMerge [
        (lib.mkIf (dmailEnabled && firefoxpwaEnabled && geckoFileExists) {
          sops.secrets.${secretName} = {
            sopsFile = geckoFile;
            key = "gecko_work_bookmark_url_1";
            path = "${dataDir}/dmail-url";
            mode = "0400";
          };

          # sops-nix creates the parent with os.ModePerm, and firefoxpwa writes
          # config.json through File::create with no mode of its own, so the
          # directory holding both the applied-URL marker and a config.json whose
          # start_url is the decrypted secret would be world-readable. Same
          # treatment and ordering as modules/home/gecko-secrets.nix.
          home.activation.ensureFirefoxpwaSecretDir =
            lib.hm.dag.entryBetween [ "sops-nix" ] [ "writeBoundary" ]
              ''
                install -d -m 700 '${dataDir}'
              '';

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
              # firefoxpwa resolves its own user data directory at runtime, from
              # FFPWA_USERDATA or else $XDG_DATA_HOME/firefoxpwa. User units do
              # not source hm-session-vars.sh, so without this a non-default
              # xdg.dataHome sends firefoxpwa's config.json somewhere the script
              # never reads: the site lookup would come back empty every run and
              # install another "DMail" on each activation. FFPWA_USERDATA rather
              # than XDG_DATA_HOME because it names the directory outright,
              # instead of relying on the "firefoxpwa" suffix the crate appends.
              Environment = [ "FFPWA_USERDATA=${dataDir}" ];
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
