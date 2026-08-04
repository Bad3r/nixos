/*
  firefoxpwa: DMail web app
  Description: Installs the primary user's work mail site as a standalone
    Progressive Web App through the firefoxpwa CLI. The start URL is never
    written to the Nix store: it is read at runtime from the SOPS-encrypted
    work-bookmark secret that modules/home/gecko-secrets.nix already stores
    (gecko.yaml key gecko_work_bookmark_url_1). The userdata directory this
    site shares with every other firefoxpwa site is pinned and hardened by
    ./home.nix, not here.

  Mechanism:
    * A oneshot user service ordered after sops-nix.service decrypts the URL and
      runs `firefoxpwa site install` with a synthetic data: manifest, so the
      site installs without the target having to serve a web manifest.
    * The install is idempotent, but only for the site this unit installed: the
      ulid firefoxpwa assigned it, the origin and the applied URL are recorded
      next to config.json, and a site merely carrying the managed name that
      those records do not account for is refused rather than adopted. A
      rotation within the recorded origin is applied in place; one that crosses
      origins is refused, because the manifest scope is fixed at install time.
    * firefoxpwa system integration writes the launcher .desktop entry and icon,
      making the app discoverable from the desktop menu.
*/
_: {
  flake.homeManagerModules.browsers.firefoxpwa =
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

      # Owned by ./home.nix, which pins and hardens it to 0700. Read rather
      # than re-derived: a second rule drifts from it as soon as either side
      # is edited, leaving the marker and config.json outside the directory
      # the hardening applies to.
      inherit (config.programs.firefoxpwa) dataDir;

      installScript = (pkgs.callPackage ../../../packages/firefoxpwa-dmail-install { }) {
        firefoxpwa = firefoxpwaPackage;
        xdgDataHome = config.xdg.dataHome;
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
              # FFPWA_USERDATA (the userdata tree, ProjectDirs) and
              # XDG_DATA_HOME (system integration's applications/ directory,
              # BaseDirs) are exported by the installer itself from the same
              # dataDir/xdgDataHome passed to it below, so the binary and the
              # script agree by construction rather than through this unit.
              Environment = [
                "FFPWA_USERDATA=${dataDir}"
                "XDG_DATA_HOME=${config.xdg.dataHome}"
              ];
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
