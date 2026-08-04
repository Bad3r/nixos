/*
  firefoxpwa: Microsoft 365 web apps
  Description: Installs the Microsoft 365 web apps declared in
    programs.firefoxpwa.m365.apps as standalone Progressive Web Apps through
    the firefoxpwa CLI, so the suite is reproduced from the configuration
    instead of clicked together in the browser extension. The userdata
    directory these sites share with every other firefoxpwa site is pinned and
    hardened by ./home.nix, not here.

  Mechanism:
    * A oneshot user service runs `firefoxpwa site install` once per entry with
      a synthetic data: manifest, so a site installs without Microsoft having
      to serve a web manifest to an unauthenticated request.
    * The install is idempotent, but only for the sites this unit installed:
      the ulid firefoxpwa assigned each one, its origin and its applied URL are
      recorded next to config.json, and a site merely carrying a managed name
      that those records do not account for is refused rather than adopted.
    * Editing an entry's URL within its recorded origin is applied in place;
      one that crosses origins is refused, because the manifest scope is fixed
      at install time.
    * firefoxpwa system integration writes the launcher .desktop entry, making
      each app discoverable from the desktop menu.

  Unlike ./dmail.nix there is no secret to wait for, so the unit is ordered
  against nothing: its ExecStart path changes whenever the app table does, and
  systemd.user.startServices = "sd-switch" (modules/home-manager/base.nix)
  restarts it on the switch that changes it.
*/
_: {
  flake.homeManagerModules.browsers.firefoxpwa =
    {
      config,
      lib,
      pkgs,
      osConfig,
      ...
    }:
    let
      # Per-host toggle declared at NixOS scope in ./apps.nix.
      m365Enabled = osConfig.programs.firefoxpwa.m365.enable or false;
      firefoxpwaEnabled = osConfig.programs.firefoxpwa.extended.enable or false;
      firefoxpwaPackage = osConfig.programs.firefoxpwa.extended.package or pkgs.firefoxpwa;
      apps = osConfig.programs.firefoxpwa.m365.apps or [ ];

      # Owned by ./home.nix, which pins and hardens it to 0700. Read rather
      # than re-derived: a second rule drifts from it as soon as either side is
      # edited, leaving the records and config.json outside the directory the
      # hardening applies to.
      inherit (config.programs.firefoxpwa) dataDir;

      installScript = (pkgs.callPackage ../../../packages/firefoxpwa-m365-install { }) {
        firefoxpwa = firefoxpwaPackage;
        xdgDataHome = config.xdg.dataHome;
        inherit dataDir apps;
      };
    in
    {
      config = lib.mkMerge [
        (lib.mkIf (m365Enabled && firefoxpwaEnabled && apps != [ ]) {
          systemd.user.services.firefoxpwa-m365 = {
            Unit.Description = "Install the Microsoft 365 web apps (firefoxpwa)";
            Service = {
              Type = "oneshot";
              RemainAfterExit = true;
              # Both are exported by the installer itself from the same
              # dataDir/xdgDataHome passed to it, so the binary and the script
              # agree by construction rather than through this unit. Set here
              # too so a manual `systemctl --user start` outside a session that
              # has the Home Manager session variables behaves identically.
              Environment = [
                "FFPWA_USERDATA=${dataDir}"
                "XDG_DATA_HOME=${config.xdg.dataHome}"
              ];
              ExecStart = lib.getExe installScript;
            };
            Install.WantedBy = [ "default.target" ];
          };
        })

        (lib.mkIf (m365Enabled && !firefoxpwaEnabled) {
          warnings = [
            "programs.firefoxpwa.m365.enable is true but programs.firefoxpwa.extended.enable is false; skipping the Microsoft 365 PWA installs."
          ];
        })

        (lib.mkIf (m365Enabled && firefoxpwaEnabled && apps == [ ]) {
          warnings = [
            "programs.firefoxpwa.m365.enable is true but programs.firefoxpwa.m365.apps is empty; skipping the Microsoft 365 PWA installs."
          ];
        })
      ];
    };
}
