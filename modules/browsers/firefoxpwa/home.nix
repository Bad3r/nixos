/*
  firefoxpwa: userdata directory pinning
  Description: Whenever programs.firefoxpwa.extended.enable is set, pins the
    firefoxpwa userdata directory into the session and hardens it to 0700, for
    every site the browser extension installs, not just any one site this repo
    also manages declaratively (see ./dmail.nix for the DMail-specific install
    layered on top of this).
*/
_: {
  flake.homeManagerModules.browsers.firefoxpwa =
    {
      config,
      lib,
      osConfig,
      ...
    }:
    let
      firefoxpwaEnabled = osConfig.programs.firefoxpwa.extended.enable or false;

      # Single source for firefoxpwa's config.json and the 0700 hardening
      # below. Derived twice they drift apart as soon as xdg.dataHome moves,
      # leaving one side pointed at a directory the other does not protect.
      dataDir = "${config.xdg.dataHome}/firefoxpwa";
    in
    {
      config = lib.mkIf firefoxpwaEnabled {
        # firefoxpwa resolves its userdata tree, and system integration its
        # applications/ directory, from the session environment: the
        # generated .desktop launcher runs `firefoxpwa site launch`, the
        # browser extension starts `firefoxpwa connector`, and the desktop
        # menu that has to find a launcher entry resolves the directory to
        # scan independently of what wrote it. Both readers are shared with
        # every site installed from the browser extension, so tying the
        # directory to a narrower toggle would move it out from under those
        # sites whenever that toggle changed. xdg.enable is off here, so
        # nothing else puts either variable into the session, and a
        # non-default xdg.dataHome would otherwise leave one side, or both,
        # resolving a directory with nothing in it.
        home.sessionVariables = {
          FFPWA_USERDATA = dataDir;
          XDG_DATA_HOME = config.xdg.dataHome;
        };

        # config.json under dataDir holds start_url for every site the
        # browser extension installs, and firefoxpwa writes it through
        # File::create with no mode of its own, under a parent left however
        # it was created. Same treatment and ordering as
        # modules/home/gecko-secrets.nix.
        home.activation.ensureFirefoxpwaSecretDir =
          lib.hm.dag.entryBetween [ "sops-nix" ] [ "writeBoundary" ]
            ''
              install -d -m 700 '${dataDir}'
            '';
      };
    };
}
